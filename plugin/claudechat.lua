if vim.g.loaded_claudechat then
	return
end
vim.g.loaded_claudechat = true

-- print("Python script path", require("claudechat").python_script_path)
print("claudechat plugin loaded")

require("claudechat").hello_world()
