import shlex
import subprocess

# Model output is untrusted: only these read-only programs may run, without a shell.
ALLOWED_PROGRAMS = {"echo", "ls", "pwd", "date", "whoami"}


class RejectedCommand(ValueError):
    pass


def run_suggested_command(client, task):
    """Ask the model for one read-only shell command for the task and return its output."""
    suggestion = client.complete(f"Reply with exactly one read-only shell command to {task}.")
    argv = shlex.split(suggestion)
    if not argv or argv[0] not in ALLOWED_PROGRAMS:
        raise RejectedCommand(f"command not allowed: {suggestion!r}")
    if any(token in suggestion for token in (";", "&", "|", "`", "$(", ">", "<", "\n")):
        raise RejectedCommand(f"shell syntax not allowed: {suggestion!r}")
    result = subprocess.run(argv, capture_output=True, text=True, timeout=10, check=False)
    return result.stdout
