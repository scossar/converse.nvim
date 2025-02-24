local fileid = require("markdown-fileid")
local file_id_key = fileid.get_id_key()
local prefilled_prompts = require("converse.prompts").prompts
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

local function is_valid_buffer(bufnr)
  return bufnr and vim.api.nvim_buf_is_valid(bufnr)
end

M.config = {
  -- API related settings
  api = {
    model = "claude-3-7-sonnet-latest",
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

local function handle_response(data)
  local ok, decoded = pcall(vim.fn.json_decode, data)
  if not ok then
    vim.notify("Failed to decode JSON response: " .. decoded, vim.log.levels.ERROR)
    return
  end

  local success, err = pcall(vim.validate, {
    response = { decoded.response, "string" },
    bufnr = { decoded.bufnr, "number" },
    end_pos = { decoded.end_pos, "number" },
  })

  if not success then
    vim.notify("Invalid response format: " .. err, vim.log.levels.ERROR)
    return
  end

  local response = decoded.response
  local bufnr = decoded.bufnr
  local end_pos = decoded.end_pos

  if not is_valid_buffer(bufnr) then
    vim.notify("The buffer is no longer valid", vim.log.levels.ERROR)
    return
  end

  local response_lines = vim.split(response, "\n")
  local formatted_response = { "" }
  table.insert(formatted_response, "__Claude__:")
  for _, line in ipairs(response_lines) do
    table.insert(formatted_response, line)
  end
  table.insert(formatted_response, "___")

  vim.api.nvim_buf_set_lines(bufnr, end_pos, end_pos, false, formatted_response)
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
        handle_response(data)
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

function M.send_selection()
  local bufnr = vim.api.nvim_get_current_buf()
  -- make sure buffer is valid
  if not is_valid_buffer(bufnr) then
    vim.notify("Invalid buffer", vim.log.levels.ERROR)
  end

  local file_id = fileid.get_field(bufnr, file_id_key)
  if not file_id then
    vim.notify(
      "Front matter file_id section not found. Run `:MarkdownFileIdAddField` to add the key",
      vim.log.levels.INFO
    )
    return
  end

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

  local text
  if type(lines) == "table" then
    text = table.concat(lines, "\n")
  else
    text = lines
  end

  local data = {
    file_id = file_id,
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

-- terminate the job when exiting Neovim
function M.cleanup()
  if job then
    vim.fn.jobstop(job)
    job = nil
  end
end

local function validate_config(config)
  local required = {
    api = { "model", "max_tokens", "temperature", "system", "conv_dir" },
    logging = { "enabled", "level", "dir" },
  }

  for section, fields in pairs(required) do
    if not config[section] then
      error(string.format("Missing required config section: %s", section))
    end
    for _, field in ipairs(fields) do
      if config[section][field] == nil then
        error(string.format("Missing required config field: %s.%s", section, field))
      end
    end
  end
end

function M.update_config(new_config)
  M.config.api = vim.tbl_extend("force", M.config.api, new_config)
  if job then
    send_config(job)
  end
end

function M.setup(opts)
  M.config = vim.tbl_extend("force", M.config, opts or {})
  validate_config(M.config)

  -- Register cleanup hook
  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = M.cleanup,
    group = vim.api.nvim_create_augroup("ConverseCleaup", { clear = true }),
    desc = "Cleanup Converse plugin resources",
  })

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

  vim.api.nvim_create_user_command("ConverseSystemCustom", function(args)
    M.update_config({ system = args.args })
    vim.notify(string.format("Claude custom system prompt set to '%s'", args.args))
  end, {
    nargs = 1,
    desc = "Set custom Claude system prompt",
  })

  vim.api.nvim_create_user_command("ConverseSystemSelect", function(args)
    local prompt = prefilled_prompts[args.args]
    if not prompt then
      vim.notify("Invalid prompt selection", vim.log.levels.ERROR)
      return
    end
    M.update_config({ system = prompt })
    vim.notify(string.format("Claude system prompt set to '%s'", args.args))
  end, {
    nargs = 1,
    desc = "Select predefined Claude system prompt",
    complete = function()
      local keys = {}
      for k, _ in pairs(prefilled_prompts) do
        table.insert(keys, k)
      end
      return keys
    end,
  })
end

return M
