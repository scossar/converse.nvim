# Converse.nvim

A Neovim plugin for chatting with Claude directly from markdown files.

I wrote the plugin to help me use LLMs as a learning tool. Switching contexts between my notes and the web UI felt like a distraction.

## Dependencies

### Neovim

The plugin requires Neovim `>= 0.9.0` and (markdown-fileid.nvim)[https://github.com/scossar/markdown-fileid.nvim].

### Python


The plugin requires Python `>= 3.7`, and the [Anthropic Python API library](https://github.com/anthropics/anthropic-sdk-python).

The easiest way I know of for dealing with Python dependencies is to use [`pip`](https://pip.pypa.io/en/stable/getting-started/):

```bash
pip install anthropic
```
Or (better) in a [virtual environment](https://packaging.python.org/en/latest/tutorials/installing-packages/#creating-virtual-environments):

```bash
python -m venv ~/.venv/converse
source ~/.venv/converse/bin/activate  # On Unix/macOS
pip install anthropic
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
  -- API related settings
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

  -- Keymapping for sending text to Claude
  mappings = {
    send_selection = "<leader>z",  -- Map for sending selected text
  }
})
```
### API options

- `model`: the Claude model to use. Currently defaults to Claude 3.5 Sonnet.
- `max_tokens`: maximum number of tokens in Claude's response.
- `temperature`: controls response randomness (0 = more deterministic, 1 = more creative).
- `system`: optional system prompt to set context for Claude.
- `conv_dir`: directory where conversation JSON files are stored.

### Loggin options

(logs data from the Python process)
- `enabled`: set to `false` to disable logging
- `level`: the log level (the default value of `"INFO"` is probably a bit much, will fix soon). Allowed levels are: `"NOTSET"` (log all messages), `"DEBUG"`, `"WARNING"`, `"ERROR"`, `"CRITICAL"`.
- `dir`: the directory the logs are saved to

### Key mappings

- `ConverseSendSelection` (mapped by default to <leader>z (for some reason))

You can change this by configuring the `mappings.send_selection` option:

```lua
require("converse").setup({
  mappings = {
    send_selection = "<your-preferred-mapping>",
  }
})
```

## Usage

1. open or create a markdown file
2. select the text you want to send to Claude (in visual mode)
3. press `<leader>z` (or your configured mapping)
4. Claude's response will be appended below your selection

The plugin maintains the conversation context for each markdown file, The conversation history is stored in JSON files in the configured `conv_dir`.

### Commands

- `:ConverseSendSelection` - send the selected text to Claude (can also be triggered with a keybinding)
- `:ConverseTemp` - adjust Claude's temperature setting (0-1)
- `:ConverseSystem` - set the system prompt. It defaults to an empty string, which works well for a lot of uses. You'll notice a difference in tone from what you get from `claude.ai` though.
- `:MarkdownFileIdAddField` - supplied by `markdown-fileid.nvim`. Adds a file ID key/value pair to a front matter section at the top of the file. If you attempt to run `:ConverseSendSelection` before adding the file ID front matter, you'll get a message asking you to run the `:MarkdownFileIdAdd` command.

## Notes

The plugin is currently only intended to be used with markdown files. That's not enforced (yet), but markdown syntax is inserted with Claude's response.

Each markdown file maps to a JSON file that's saved in the `conv_dir`. The file ID added by `:MarkdownFileIdAddField` is used to match each markdown file with the relevant JSON file.

The text you send to Claude, and Claude's responses are saved to the file. For example:

```json
  {
    "role": "user",
    "content": "For these cases, does the term \"evaluation metric\" refer to what is being used to determine if the model is doing well in a specific area? For example, the evaluation metric could be the classification error?"
  },
  {
    "role": "assistant",
    "content": "Yes, that's correct! An evaluation metric is a specific measure or criterion used to assess how well a model is performing at its intended task. Classification error is indeed one example of an evaluation metric.\n\nHere are some common evaluation metrics..."
  },
  {
    "role": "user",
    "content": "Can you help me understand the difference between precision and recall in this context?"
  },
  {
    "role": "assistant",
    "content": "Yes! Precision and Recall are both important metrics in classification problems, but they focus on different aspects of performance. Let me explain with an example..."
  },
```

Log files are rotated when they reach ~1MB (1024 * 1024 bytes). A maximum of 5 log files are kept. Note that you can turn off logging with the `logging.enabled` option. (Without logging, it can be tricky to debug issues on the Python end of things.) 

## Todo

- prevent `:ConverseSendSelection` from being run on non-markdown files
- add an option to make the text that's prepended to Claude's responses configurable
- allow selected question/response pairs to be copied from a conversation's JSON file to a new conversation

Feel free to report any issues or bugs you run into.

