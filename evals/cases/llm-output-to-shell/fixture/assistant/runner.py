import subprocess


def run_suggested_command(client, task):
    """Ask the model for one read-only shell command for the task and return its output."""
    suggestion = client.complete(f"Reply with exactly one read-only shell command to {task}.")
    result = subprocess.run(suggestion, shell=True, capture_output=True, text=True, timeout=10)
    return result.stdout
