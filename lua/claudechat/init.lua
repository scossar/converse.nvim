local M = {}

local plugin_path = debug.getinfo(1).source:sub(2):match("(.*)/lua/")
local python_script_path = plugin_path .. "/python/nvim_conversation_manager.py"

local function send_to_python(job_id, message)
  vim.fn.chansend(job_id, message .. "\n")
end

local function create_job()
  return vim.fn.jobstart({ "python", python_script_path }, {
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
end

local job = nil

function M.send_selection()
  local bufnr = vim.api.nvim_get_current_buf()
  local start_pos = vim.fn.getpos("'<")[2]
  local end_pos = vim.fn.getpos("'>")[2]
  if not job then
    job = create_job()
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

return M
