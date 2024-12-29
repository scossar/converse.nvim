import sys
import json
import logging
from pathlib import Path
from anthropic import Anthropic

# logging.basicConfig(
#     filename="converse.log",
#     level=logging.DEBUG,
#     format="%(asctime)s - %(levelname)s - %(message)s"
# )


class NvimConversationManager:
    def __init__(self):
        # self.logger = logging.getLogger(__name__)
        self.logger = None
        self.conv_dir = None
        self.conv_name = None
        self.json_file = None
        self.messages = None
        self.client = Anthropic()
        self.config = {}
        self.logging_enabled = False

    def setup_logging(self):
        logging_config = self.config["logging"]
        log_level = logging_config["level"]
        log_dir = Path(logging_config["dir"])

        if log_dir.is_file():
            raise ValueError(f"Logging path exists but is a file: {log_dir}")

        self.logging_enabled = logging_config["enabled"]
        self.logger = logging.getLogger(__name__)

        if not self.logging_enabled:
            self.logger.handlers.clear()
            self.logger.addHandler(logging.NullHandler())
            return

        try:
            log_dir.mkdir(parents=True, exist_ok=True)
        except PermissionError:
            raise ValueError(f"No permission to create logging directory: {log_dir}")
        except OSError as e:
            raise ValueError(f"Failed to create logging directory: {log_dir} - {str(e)}")

        log_file = log_dir / "converse.log"

        try:
            log_file.touch(exist_ok=True)
        except (PermissionError, OSError) as e:
            raise ValueError(f"Cannot write to log file {log_file}: {str(e)}")

        logging.basicConfig(
            filename=str(log_file),
            level=log_level,
            format="%(asctime)s - %(levelname)s - %(message)s"
        )
        self.logger.info(f"Logging initialized with: {logging_config}")

    # def setup_logging(self):
    #     logging_config = self.config["logging"]
    #     log_level = logging_config["level"]
    #     log_dir = Path(logging_config["dir"])
    #     self.logging_enabled = logging_config["enabled"]
    #
    #     log_dir.mkdir(parents=True, exist_ok=True)
    #     log_file = log_dir / "converse.log"
    #
    #     logging.basicConfig(
    #         filename=str(log_file),
    #         level=log_level,
    #         format="%(asctime)s - %(levelname)s - %(message)s"
    #     )
    #     self.logger = logging.getLogger(__name__)
    #     self.logger.info(f"Logging initialized with: {logging_config}")

    def update_config(self, new_config: dict):
        if not all(key in new_config for key in ["api", "logging"]):
            raise ValueError("Missing required config sections: api and/or logging")

        api_config = new_config.get("api", {})
        logging_config = new_config.get("logging", {})

        required_api_keys = ["model", "max_tokens", "temperature", "conv_dir", "system"]
        missing_keys = [key for key in required_api_keys if key not in api_config]
        required_logger_keys = ["enabled", "level", "dir"]
        missing_keys.extend([key for key in required_logger_keys if key not in logging_config])
        if missing_keys:
            raise ValueError(f"Missing required config keys: {', '.join(missing_keys)}")

        if not isinstance(api_config["max_tokens"], int) or api_config["max_tokens"] <= 0:
            raise ValueError("max_tokens must be a positive integer")

        if not isinstance(api_config["temperature"],
                          (int, float)) or not 0 <= api_config["temperature"] <= 2:
            raise ValueError("temperature must be a number between 0 and 2")

        if not isinstance(api_config["conv_dir"], str) or not api_config["conv_dir"]:
            raise ValueError("conv_dir must be a non-empty string")

        if not isinstance(logging_config["enabled"], bool):
            raise ValueError("logging.enabled must be a boolean")

        if not isinstance(logging_config["dir"], str) or not logging_config["dir"]:
            raise ValueError("logging.dir must be a non-empty string")

        self.config.update(new_config)

        try:
            self.setup_logging()
        except ValueError as e:
            raise ValueError(f"Failed to setup logging: {str(e)}")

        if self.logging_enabled:
            self.logger.info(f"New config state: {self.config}")

        try:
            self.conv_dir = Path(self.config["api"]["conv_dir"])
            self.conv_dir.mkdir(parents=True, exist_ok=True)
        except PermissionError:
            raise ValueError(f"No permission to create conversation directory: {self.conv_dir}")
        except OSError as e:
            raise ValueError(f"Failed to create conversation directory: {self.conv_dir} - {str(e)}")

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
        # TODO: handle the case of api not being set
        api_config = config.get("api")
        self.logger.info(f"Sending message with config: {config}")

        response = self.client.messages.create(
            model=api_config["model"],
            max_tokens=api_config["max_tokens"],
            temperature=api_config["temperature"],
            system=api_config["system"],
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

