-- screenshots-to-photos : Folder Action script
-- Watches a folder; every new image dropped in is imported into Photos,
-- and the source file is deleted ONLY after a successful import.
-- Fail-safe: if the import throws, the file stays in the folder as evidence.

on adding folder items to thisFolder after receiving addedItems
	repeat with f in addedItems
		set p to POSIX path of f
		set fname to do shell script "basename " & quoted form of p
		if fname does not start with "." then
			try
				tell application "Photos"
					import {POSIX file p as alias} skip check duplicates true
				end tell
				-- reached only if the import above did not error
				do shell script "rm " & quoted form of p
			end try
		end if
	end repeat
end adding folder items to
