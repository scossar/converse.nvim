# Converse.nvim

A Neovim plugin for chatting with Claude directly from markdown files.

## Dependencies

### Neovim

Neovim `>= 0.9.0` and [markdown-fileid.nvim](https://github.com/scossar/markdown-fileid.nvim).

### Python

Python `>= 3.7`, and the [Anthropic Python API library](https://github.com/anthropics/anthropic-sdk-python)

NOTE: The plugin assumes that `g:python3_host_prog` is configured and that the Anthropic Python API library is installed in that environment. See `:help python3_host_prog` for some details about configuring the Python virtual env. Essentially, after creating a virtual env with a tool like Mise or Pyenv, add something like the following to your `init.lua` file:

```lua
vim.g.python3_host_prog = vim.fn.expand("~/path/to/virtual_env/bin/python")
```

The plugin also requires an Anthropic API key and assumes that `ANTHROPIC_API_KEY` is set as an environmental variable. For example, in your `~/.bashrc` file:

```bash
export ANTHROPIC_API_KEY='your_anthropic_api_key'
```

## Installation

### Using lazy.nvim

```lua
{
  "scossar/converse.nvim",
  dependencies = { "scossar/markdown-fileid.nvim" },
  config = function()
    require("converse").setup({
      -- configuration options (see below)
    })
  end
}
```

## Configuration

### Default Configuration

```lua
require("converse").setup({
  api = {
    model = "claude-3-5-sonnet-20241022",  -- The Claude model to use
    max_tokens = 8192,                      -- Maximum tokens in the response
    temperature = 0.7,                      -- Response temperature (0-1)
    system = "",                           -- System prompt (if needed)
    conv_dir = "~/.local/share/converse/conversations"  -- Where conversation histories are stored
  },

  logging = {
    enabled = true,
    level = "INFO",
    dir = vim.fn.stdpath("data") .. "/converse/logs",  -- usually `~/.local/share/nvim/converse/logs` on Linux
  },

  -- key mapping for sending text to Claude
  mappings = {
    send_selection = "<leader>z",  -- Map for sending selected text
  }
})
```

### API options

- `model`: the Claude model to use. Currently defaults to Claude 3.5 Sonnet
- `max_tokens`: maximum number of tokens in Claude's response
- `temperature`: controls response randomness (0 = more deterministic, 1 = more creative)
- `system`: optional system prompt to set context for Claude
- `conv_dir`: directory where conversation JSON files are stored

### Loggin options

(logs data from the Python process)

- `enabled`: set to `false` to disable logging
- `level`: the log level (the default value of `"INFO"` is probably a bit much, will fix soon). Allowed levels are: `"NOTSET"` (log all messages), `"DEBUG"`, `"WARNING"`, `"ERROR"`, `"CRITICAL"`.
- `dir`: the directory that logs are saved to

### Key mappings

- `ConverseSendSelection` (mapped by default to <leader>z (for some reason))

You can change this with the `mappings.send_selection` option:

```lua
require("converse").setup({
  mappings = {
    send_selection = "<your-preferred-mapping>",
  }
})
```

## Usage

1. open or create a markdown file
2. add a `file_id` front matter section using the `:MarkdownFileIdAddField` command
3. select the text you want to send to Claude (in visual mode)
4. press `<leader>z` (or your configured mapping)
5. Claude's response will be appended below your selection

### Commands

- `:ConverseSendSelection` - send the selected text to Claude (can also be triggered with a keybinding)
- `:ConverseTemp` - adjust Claude's temperature setting (0-1)
- `:ConverseSystemCustom` - set a custom system prompt
- `:ConverseSystemSelect` - select from a list of system prompts (currently claude_3_5_sonnet: [docs.anthropic.com/en/release-notes/system-prompts#nov-22nd-2024](https://docs.anthropic.com/en/release-notes/system-prompts#nov-22nd-2024))
- `:MarkdownFileIdAddField` - supplied by `markdown-fileid.nvim`. Adds a file ID key/value pair to a front matter section at the top of the file. If you attempt to run `:ConverseSendSelection` before adding the file ID front matter, you'll get a message asking you to run the `:MarkdownFileIdAdd` command.

## Notes

The plugin is only intended to be used with markdown files. That's not enforced (yet), but markdown syntax is inserted with Claude's response.

Any markdown file you start a conversation in maps to a JSON file that's saved in the `conv_dir` directory. The file ID added by `:MarkdownFileIdAddField` is used to match each markdown file with the relevant JSON file.

Log files are rotated when they reach ~1MB (1024 * 1024 bytes). A maximum of 5 log files are kept. You can turn off logging with the `logging.enabled` option.

The system prompt defaults to an empty string. That works fine for many cases.

## Todo

- make the text that's prepended to Claude's responses configurable
- allow some of the context of a conversation to be copied to a new file

Feel free to report any issues or bugs you run into.
