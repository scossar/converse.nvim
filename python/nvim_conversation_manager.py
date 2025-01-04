import sys
import json
import logging
import importlib
from logging.handlers import RotatingFileHandler
from pathlib import Path
from anthropic import Anthropic


class NvimConversationManager:
    def __init__(self):
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
        self.logger.handlers.clear()  # clear any existing handlers

        if not self.logging_enabled:
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

        handler = RotatingFileHandler(
            filename=str(log_file),
            maxBytes=1024 * 1024,
            backupCount=5,
            encoding="utf-8"
        )

        formatter = logging.Formatter("%(asctime)s - %(levelname)s - %(message)s")
        handler.setFormatter(formatter)
        handler.setLevel(log_level)

        self.logger.addHandler(handler)
        self.logger.setLevel(log_level)

        self.logger.info(f"Logging initialized with: {logging_config}")

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
        try:
            with open(self.json_file, "w", encoding='utf-8') as f:
                json.dump(messages, f, indent=2)
        except IOError as e:
            self.logger.error(f"Failed to write conversation to {self.json_file}: {str(e)}")
            raise ValueError(f"Failed to save conversation: {str(e)}")
        except json.JSONEncodeError as e:
            self.logger.error(f"Failed to serialize conversation data: {str(e)}")
            raise ValueError(f"Failed to encode conversation data: {str(e)}")

        self.logger.debug(f"Saved conversation to {self.json_file}")

    def append_message(self, role: str, content: str):
        message = {}
        message["role"] = role
        message["content"] = content
        self.messages.append(message)

    def send_messages(self) -> str:
        try:
            api_config = self.config.get("api")
            if not api_config:
                raise ValueError("API configuration is missing")

            self.logger.info(f"Sending message with config: {api_config}")

            try:
                response = self.client.messages.create(
                    model=api_config["model"],
                    max_tokens=api_config["max_tokens"],
                    temperature=api_config["temperature"],
                    system=api_config["system"],
                    messages=self.messages
                )
            except Exception as e:
                self.logger.error(f"API call failed: {str(e)}")
                raise ValueError(f"Failed to get response from Anthropic API: {str(e)}")

            if not response or not response.content:
                self.logger.error("Received empty response from API")
                raise ValueError("Received empty response from API")

            try:
                content = response.content[0].text
            except (IndexError, AttributeError) as e:
                self.logger.error(f"Failed to extract content from response: {str(e)}")
                raise ValueError(f"Unexpected response format: {str(e)}")

            self.append_message("assistant", content)
            self.save_conversation(self.messages)

            self.logger.debug("Successfully received and saved response")
            return content

        except Exception as e:
            self.logger.error(f"Error in send_messages: {str(e)}")
            raise


def check_dependencies():
    try:
        importlib.import_module("anthropic")
    except ImportError:
        print("Required package 'anthropic' is not installed", file=sys.stderr)
        sys.exit(1)


def read_input():
    try:
        line = sys.stdin.readline()
        if not line:
            return None
        return json.loads(line)
    except IOError as e:
        raise ValueError(f"Failed to read from stdin: {str(e)}")
    except json.JSONDecodeError as e:
        raise ValueError(f"Invalid JSON received: {str(e)}")


def handle_config(ncm, data):
    if "config" not in data:
        raise ValueError("Config message missing 'config' field")
    ncm.update_config(data["config"])


def validate_data(data):
    if not isinstance(data, dict):
        raise ValueError("Input must be a JSON object")
    required_fields = ["file_id", "content", "bufnr", "end_pos"]
    missing_fields = [field for field in required_fields if field not in data]
    if missing_fields:
        raise ValueError(f"Missing required fields: {', '.join(missing_fields)}")


def process_message(ncm, data):
    conversation_name = data["file_id"]
    ncm.load_conversation(conversation_name)
    ncm.append_message("user", data["content"])
    return ncm.send_messages()


def send_response(response, bufnr, end_pos):
    try:
        print(json.dumps({
            "response": response,
            "bufnr": bufnr,
            "end_pos": end_pos
        }), flush=True)
    except (IOError, json.JSONEncodeError) as e:
        raise ValueError(f"Failed to send response: {str(e)}")


def main():
    try:
        check_dependencies()
        ncm = NvimConversationManager()

        while True:
            try:

                data = read_input()
                if data is None:
                    break

                if data.get("type") == "config":
                    handle_config(ncm, data)
                    continue

                validate_data(data)
                response = process_message(ncm, data)
                send_response(response, data["bufnr"], data["end_pos"])

            except Exception as e:
                print(json.dumps({
                    "error": str(e)
                }), file=sys.stderr, flush=True)

    except Exception as e:
        sys.stderr.write(f"Critical error: {str(e)}\n")
        sys.exit(1)


if __name__ == "__main__":
    main()
