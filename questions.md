# Open questions

- Should static-checker errors follow a fixed order? Defer until optimization-loop work: reordering an invalid schedule can change its first reported conflict, but not its rejection.
