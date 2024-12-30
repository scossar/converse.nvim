local M = {}

local plugin_path = debug.getinfo(1).source:sub(2):match("(.*)/lua/")
local python_script_path = plugin_path .. "/python/nvim_conversation_manager.py"

local highlight_ns = vim.api.nvim_create_namespace("converse_highlight")

local function send_to_python(job_id, message)
  if vim.fn.jobwait({ job_id }, 0)[1] ~= -1 then
    error("Invalid or terminated job_id")
  end

  local ok, err = pcall(vim.fn.chansend, job_id, message .. "\n")
  if not ok then
    error(string.format("Failed to send message to Python process: %s", err))
  end
end

M.config = {
  -- API related settings
  api = {
    model = "claude-3-5-sonnet-20241022",
    max_tokens = 8192,
    temperature = 0.7,
    system = "",
    conv_dir = vim.fn.expand("~/.local/share/converse/conversations"),
  },

  logging = {
    enabled = true,
    level = "INFO",
    dir = vim.fn.stdpath("data") .. "/converse/logs",
  },

  -- plugin specific settings
  mappings = {
    send_selection = "<leader>z",
  },
}

local function send_config(job_id)
  local config_data = {
    type = "config",
    config = {
      api = M.config.api,
      logging = M.config.logging,
    },
  }

  local encoded_ok, encoded = pcall(vim.fn.json_encode, config_data)

  if not encoded_ok then
    vim.notify("Failed to encode JSON:" .. encoded, vim.log.levels.ERROR)
    return false, "JSON encoding failed"
  end

  local send_ok, err = pcall(send_to_python, job_id, encoded)
  if not send_ok then
    vim.notify(string.format("Failed to send message to Python process: %s", err), vim.log.levels.ERROR)
    return false, "Failed to send configuration"
  end

  return true
end

local job = nil

local function create_job(on_response)
  local job_id = vim.fn.jobstart({ "python", python_script_path }, {
    on_exit = function(_, exit_code)
      job = nil -- clear job reference when process exits
      if exit_code ~= 0 then
        vim.notify("Python process exited with code: " .. exit_code, vim.log.levels.ERROR)
      end
    end,

    on_stdout = function(_, data)
      if data and data[1] and data[1] ~= "" then
        if on_response then
          vim.schedule(function()
            on_response()
          end)
        end
        local ok, decoded = pcall(vim.fn.json_decode, data[1])

        if not ok then
          vim.notify("Failed to decode JSON response:" .. decoded, vim.log.levels.Error)
          return
        end

        local response = decoded.response
        local bufnr = decoded.bufnr
        local end_pos = decoded.end_pos

        local missing_props = {}
        if not response then
          table.insert(missing_props, "response")
        end
        if not bufnr then
          table.insert(missing_props, "bufnr")
        end
        if not end_pos then
          table.insert(missing_props, "end_pos")
        end

        if #missing_props > 0 then
          local error_msg =
            string.format("Missing required properties in API response: %s", table.concat(missing_props, ", "))
          vim.notify(error_msg, vim.log.levels.Error)
          return
        end

        local response_lines = vim.split(response, "\n")
        local formatted_response = { "" }
        table.insert(formatted_response, "### Claude")
        for _, line in ipairs(response_lines) do
          table.insert(formatted_response, line)
        end
        table.insert(formatted_response, "___")

        if vim.api.nvim_buf_is_valid(bufnr) then
          vim.api.nvim_buf_set_lines(bufnr, end_pos, end_pos, false, formatted_response)
        else
          vim.notify("Buffer no longer valid", vim.log.levels.WARN)
        end
      end
    end,

    on_stderr = function(_, data)
      -- concatenate the error output
      if data and #data > 0 then
        -- filter out empty lines and concatenate with newlines
        local error_lines = vim.tbl_filter(function(line)
          return line and line ~= ""
        end, data)

        if #error_lines > 0 then
          local error_msg = table.concat(error_lines, "\n")
          vim.notify(string.format("Python error:\n%s", error_msg), vim.log.levels.ERROR)
          return
        end
      end
    end,
  })

  if job_id <= 0 then
    vim.notify("Failed to start Python process", vim.log.levels.ERROR)
    return nil
  end

  local ok, err = pcall(send_config, job_id)
  if not ok then
    vim.notify(string.format("Error sending config: %s", err), vim.log.levels.ERROR)
    return nil
  end
  return job_id
end

local function path_to_conversation_name(buffer_path)
  -- First expand the full path to handle ~
  local full_path = vim.fn.expand(buffer_path)
  -- Then get the path relative to home
  local home_relative = vim.fn.fnamemodify(full_path, ":~")
  -- Replace both ~ and / with _ and remove any leading _ characters
  return home_relative:gsub("[~/]", "_"):gsub("^_+", "")
end

function M.send_selection()
  local bufnr = vim.api.nvim_get_current_buf()
  local start_pos = vim.fn.getpos("'<")[2]
  local end_pos = vim.fn.getpos("'>")[2]

  -- add highlight to the selected region
  for i = start_pos, end_pos do
    vim.api.nvim_buf_add_highlight(bufnr, highlight_ns, "ConverseSent", i - 1, 0, -1)
  end

  -- store the notification handle so it can be updated in the job callback
  local notify_handle = vim.notify("Sending request to Claude...", vim.log.levels.INFO)

  if not job or vim.fn.jobwait({ job }, 0)[1] == -1 then
    job = create_job(function()
      vim.api.nvim_buf_clear_namespace(bufnr, highlight_ns, 0, -1)
      vim.notify("Response received from Claude", vim.log.levels.INFO, {
        replace = notify_handle,
      })
    end)
    if not job then
      return
    end
  end

  local lines = vim.fn.getline(start_pos, end_pos)
  local buffer_path = vim.api.nvim_buf_get_name(0)
  local conversation_name = path_to_conversation_name(buffer_path)

  local text
  if type(lines) == "table" then
    text = table.concat(lines, "\n")
  else
    text = lines
  end

  local data = {
    filename = conversation_name,
    bufnr = bufnr,
    end_pos = end_pos,
    content = text,
  }

  local encoded_ok, json = pcall(vim.fn.json_encode, data)
  if not encoded_ok then
    vim.notify(string.format("Failed to encode JSON: %s", json), vim.log.levels.ERROR)
    return
  end

  local send_ok, err = pcall(send_to_python, job, json)
  if not send_ok then
    vim.notify(string.format("Failed to send message to Python process: %s", err), vim.log.levels.ERROR)
    return
  end

  -- move the cursor to the end of the selection
  vim.api.nvim_win_set_cursor(0, { end_pos, 0 })
end

function M.update_config(new_config)
  M.config.api = vim.tbl_extend("force", M.config.api, new_config)
  if job then
    send_config(job)
  end
end

function M.setup(opts)
  M.config = vim.tbl_extend("force", M.config, opts or {})

  -- get colors from the color scheme to highlight the selected text
  local visual_hl = vim.api.nvim_get_hl(0, { name = "Search" })
  local bg_color = visual_hl.bg

  if bg_color then
    local bg_hex = string.format("#%06x", bg_color)
    vim.api.nvim_set_hl(0, "ConverseSent", {
      bg = bg_hex,
      blend = 20,
    })
  else
    vim.api.nvim_set_hl(0, "ConverseSent", { bg = "#3a405a", blend = 20 })
  end

  vim.api.nvim_create_user_command("ConverseSendSelection", function()
    M.send_selection()
  end, {
    range = true,
    desc = "Send selection to Claude",
  })

  if M.config.mappings.send_selection then
    vim.keymap.set(
      "v",
      M.config.mappings.send_selection,
      ":ConverseSendSelection<CR>",
      { desc = "[A]sk Claude", noremap = true, silent = true }
    )
  end

  vim.api.nvim_create_user_command("ConverseTemp", function(args)
    -- trim whitespace and convert commas to decimal points
    local cleaned_input = args.args:match("^%s*(.-)%s*$"):gsub(",", ".")
    local temp = tonumber(cleaned_input)
    if temp and temp >= 0 and temp <= 1 then
      M.update_config({ temperature = temp })
      vim.notify(string.format("Claude temperature set to %.2f", temp))
    else
      vim.notify(
        string.format("Invalid temperature value: '%s'. Must be between 0 and 1", args.args),
        vim.log.levels.Error
      )
    end
  end, {
    nargs = 1,
    desc = "Set Claude temperature (0-1)",
    complete = function()
      return { "0", "0.3", "0.5", "0.7", "1" }
    end,
  })

  vim.api.nvim_create_user_command("ConverseSystem", function(args)
    local system_prompt = args.args
    M.update_config({ system = system_prompt })
    vim.notify(string.format("Claude system prompt set to '%s'", system_prompt))
  end, {
    nargs = 1,
    desc = "Set Claude system prompt",
  })
end

return M
