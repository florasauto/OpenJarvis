# Floras Auto roles
#
# The office fills this in. The unit intake checker names an owner for each
# open item only from this list. While the list is empty, it writes
# "owner: unassigned" instead of guessing.
#
# One role per line, written as:   Role: what that role owns
# Lines that start with # are ignored. After editing, rerun
# scripts/floras-auto/setup-intake-checker.sh so the checker picks it up.
#
# Example of the format only. Replace with the team's real roles and remove
# the leading "# " from each line you want used:
#
# Office manager: titles, paperwork, anything past a deadline
# Yard lead: yard locations, keys, photos
