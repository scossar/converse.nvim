import sys
import json
import logging
from pathlib import Path
from anthropic import Anthropic

logging.basicConfig(
    filename="converse.log",
    level=logging.DEBUG,
    format="%(asctime)s - %(levelname)s - %(message)s"
)


class NvimConversationManager:
    def __init__(self):
        self.logger = logging.getLogger(__name__)
        self.conv_dir = None
        self.conv_name = None
        self.json_file = None
        self.messages = None
        self.client = Anthropic()
        self.config = {
            "model": "claude-3-5-sonnet-20241022",
            "max_tokens": 8192,
            "temperature": 0.7,
            "system": "",
            "conv_dir": ""
        }

    def update_config(self, new_config: dict):
        self.logger.debug(f"Updating config with: {new_config}")
        self.config.update(new_config)
        self.logger.debug(f"New config state: {self.config}")
        if self.config["conv_dir"]:
            self.conv_dir = Path(self.config["conv_dir"])
            self.conv_dir.mkdir(parents=True, exist_ok=True)

    def set_conversation(self, name: str):
        if not self.conv_dir:
            raise ValueError("Conversation directory not set. Please configure conv_dir setting.")

        self.conv_name = name
        self.json_file = self.conv_dir / f"{name}.json"

    def load_conversation(self, name: str):
        self.set_conversation(name)
        try:
            with open(self.json_file, "r") as f:
                messages = json.load(f)
        except FileNotFoundError:
            messages = []
        self.messages = messages

    def save_conversation(self, messages: list):
        with open(self.json_file, "w") as f:
            json.dump(messages, f, indent=2)

    def append_message(self, role: str, content: str):
        message = {}
        message["role"] = role
        message["content"] = content
        self.messages.append(message)

    def send_messages(self, **kwargs) -> str:
        # merge instance config with any provided overrides
        config = {**self.config, **kwargs}
        self.logger.debug(f"Sending message with config: {config}")

        response = self.client.messages.create(
            model=config["model"],
            max_tokens=config["max_tokens"],
            temperature=config["temperature"],
            system=config["system"],
            messages=self.messages
        )

        content = response.content[0].text
        self.append_message("assistant", content)
        self.save_conversation(self.messages)
        return content


def main():
    ncm = NvimConversationManager()

    while True:
        try:
            line = sys.stdin.readline()
            if not line:
                break

            data = json.loads(line)

            if data.get("type") == "config":
                ncm.update_config(data["config"])
                continue

            filename = data["filename"]
            conversation_name = Path(filename).stem
            content = data["content"]
            bufnr = data["bufnr"]
            end_pos = data["end_pos"]

            ncm.load_conversation(conversation_name)
            ncm.append_message("user", content)
            response = ncm.send_messages()
            print(json.dumps({
                "response": response,
                "bufnr": bufnr,
                "end_pos": end_pos
            }), flush=True)

        except Exception as e:
            print(json.dumps({
                "error": str(e)
            }), file=sys.stderr, flush=True)


if __name__ == "__main__":
    main()
