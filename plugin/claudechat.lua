if vim.g.loaded_claudechat then
  return
end
vim.g.loaded_claudechat = true

vim.api.nvim_create_user_command("ClaudeChatSendSelection", function()
  require("claudechat").send_selection()
end, { range = true })

vim.keymap.set(
  "v",
  "<leader>z",
  ":ClaudeChatSendSelection<CR>",
  { desc = "[A]sk Claude", noremap = true, silent = true }
)
