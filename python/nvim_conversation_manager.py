import sys
import json
from pathlib import Path
from anthropic import Anthropic


class NvimConversationManager:
    def __init__(self, conv_dir: Path = Path("/home/scossar/nvim_claude")):
        self.conv_dir = conv_dir
        if not self.conv_dir.exists():
            raise ValueError(f"Conversation directory '{self.conv_dir}' doesn't exist")
        self.conv_name = None
        self.json_file = None
        self.messages = None
        self.client = Anthropic()

    def set_conversation(self, name: str):
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

    def send_messages(self) -> str:
        response = self.client.messages.create(
            model="claude-3-5-sonnet-20241022",
            max_tokens=8192,
            temperature=0.7,
            messages=self.messages
        )

        content = response.content[0].text
        self.append_message("assistant", content)
        self.save_conversation(self.messages)
        return content


def main():
    while True:
        try:
            line = sys.stdin.readline()
            if not line:
                break

            data = json.loads(line)
            print(json.dumps({
                "response": data["content"]
            }), flush=True)

        except Exception as e:
            print(json.dumps({
                "error": str(e)
            }), file=sys.stderr, flush=True)


if __name__ == "__main__":
    main()


# def main():
#     while True:
#         try:
#             line = sys.stdin.readline()
#             if not line:
#                 break
#
#             # Parse JSON input
#             data = json.loads(line)
#
#             # Process with Anthropic API
#             client = Anthropic()
#             response = client.messages.create(
#                 model=data.get("model", "claude-2"),
#                 max_tokens=data.get("max_tokens", 1000),
#                 messages=[{"role": "user", "content": data["prompt"]}]
#             )
#
#             # Send JSON response
#             print(json.dumps({
#                 "response": response.content[0].text
#             }), flush=True)
#
#         except Exception as e:
#             print(json.dumps({
#                 "error": str(e)
#             }), file=sys.stderr, flush=True)
#
#
# if __name__ == "__main__":
#     main()
