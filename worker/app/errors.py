class PermanentError(Exception):
    """Failure that retrying won't fix (bad PDF, profile not found, blocked content).

    The worker marks the roast as failed right away and answers 200 so Cloud Tasks
    doesn't burn retries. `user_message` is shown in the UI (Spanish).
    """

    def __init__(self, user_message: str, detail: str = ""):
        super().__init__(detail or user_message)
        self.user_message = user_message
