# Preview release notes

Start `changelog.txt` with an entry for each AI Edition preview, using
`VERSION[<manifest version>][YYYY/MM/DD]` followed by the user-visible changes.
Keep older entries so people who skip previews can see the available history.
Update the manifest version and hashes along with the release notes.

The update dialog reads notes from the downloaded update and verifies them
against its staged manifest. It identifies gaps in preview history and missing
notes instead of treating older installed notes as new. Older installed versions
gain this behavior after applying an update that includes it.
