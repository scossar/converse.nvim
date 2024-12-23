local M = {}

local plugin_path = debug.getinfo(1).source:sub(2):match("(.*)/lua/")
local python_script_path = plugin_path .. "/python/nvim_conversation_manager.py"

local function send_to_python(job_id, message)
	vim.fn.chansend(job_id, message .. "\n")
end

local job = vim.fn.jobstart({ "python", python_script_path }, {
	on_stdout = function(_, data)
		if data and data[1] and data[1] ~= "" then
			-- Handle response from Python
			local response = data[1]
			-- Process response...
			print("response:", response)
		end
	end,
	on_stderr = function(_, data)
		if data and data[1] and data[1] ~= "" then
			print("Error:", data[1])
		end
	end,
})

local data = {
	filename = "plugin_test.md",
	content = "hello from Neovim!",
}
local json = vim.fn.json_encode(data)

M.hello_world = function()
	send_to_python(job, json)
end

return M
