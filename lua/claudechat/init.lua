local M = {}

local plugin_path = debug.getinfo(1).source:sub(2):match("(.*)/lua/")
local python_script_path = plugin_path .. "/python/nvim_conversation_manager.py"

local function send_to_python(job_id, message)
  vim.fn.chansend(job_id, message .. "\n")
end

M.config = {
  -- API related settings
  api = { model = "claude-3-5-sonnet-20241022", max_tokens = 8192, temperature = 0.7, system = "" },

  -- plugin specific settings
  mappings = {
    send_selection = "<leader>z",
  },
}

local function send_config(job_id)
  local config_data = {
    type = "config",
    config = M.config.api,
  }

  send_to_python(job_id, vim.fn.json_encode(config_data))
end

local job = nil

local function create_job()
  local job_id = vim.fn.jobstart({ "python", python_script_path }, {
    on_exit = function(_, exit_code)
      job = nil -- clear job reference when process exits
      if exit_code ~= 0 then
        vim.notify("Python process exited with code: " .. exit_code, vim.log.levels.ERROR)
      end
    end,

    on_stdout = function(_, data)
      if data and data[1] and data[1] ~= "" then
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
      if data and data[1] and data[1] ~= "" then
        print("Error:", data[1])
      end
    end,
  })

  if job_id <= 0 then
    vim.notify("Failed to start Python process", vim.log.levels.ERROR)
    return nil
  end

  send_config(job_id)
  return job_id
end

function M.send_selection()
  local bufnr = vim.api.nvim_get_current_buf()
  local start_pos = vim.fn.getpos("'<")[2]
  local end_pos = vim.fn.getpos("'>")[2]
  if not job or vim.fn.jobwait({ job }, 0)[1] == -1 then
    job = create_job()
    if not job then
      return
    end
  end

  local lines = vim.fn.getline(start_pos, end_pos)
  local buffer_path = vim.api.nvim_buf_get_name(0)

  local text
  if type(lines) == "table" then
    text = table.concat(lines, "\n")
  else
    text = lines
  end

  local data = {
    filename = buffer_path,
    bufnr = bufnr,
    end_pos = end_pos,
    content = text,
  }
  local json = vim.fn.json_encode(data)

  vim.notify("Sending request to Claude...", vim.log.levels.INFO)

  send_to_python(job, json)
end

function M.update_config(new_config)
  M.config.api = vim.tbl_extend("force", M.config.api, new_config)
  if job then
    send_config(job)
  end
end

function M.setup(opts)
  M.config = vim.tbl_extend("force", M.config, opts or {})

  if M.config.mappings.send_selection then
    vim.keymap.set(
      "v",
      M.config.mappings.send_selection,
      ":ClaudeChatSendSelection<CR>",
      { desc = "[A]sk Claude", noremap = true, silent = true }
    )
  end

  vim.api.nvim_create_user_command("ClaudeTemp", function(args)
    local temp = tonumber(args.args)
    if temp and temp >= 0 and temp <= 1 then
      M.update_config({ temperature = temp })
      vim.notify(string.format("Claude temperature set to %.1f", temp))
    else
      vim.notify("Temperature must be between 0 and 1", vim.log.levels.Error)
    end
  end, {
    nargs = 1,
    desc = "Set Claude temperature (0-1)",
    complete = function()
      return { "0", "0.3", "0.5", "0.7", "1" }
    end,
  })
end

return M
