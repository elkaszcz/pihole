# Consolidate Pi-hole Blocking Lists

This script helps you merge multiple Pi-hole blocking lists (local files or remote URLs) into a single de-duplicated hosts file.

## Features
- Accepts a list of sources (`.txt` file containing URLs or local file paths).
- Downloads lists with `curl --compressed` (for remote URLs).
- Cleans and extracts domains, removes duplicates, sorts them.
- Outputs a Pi-hole-compatible hosts file in the format:
  ```
  0.0.0.0 example.com
  ```
- Handles large lists efficiently (tens of MBs).

## Requirements
- macOS (works on M1/M2 and Intel Macs).
- Default tools: `bash`, `awk`, `sort`, `curl`.

No extra dependencies required.

## Usage

1. Save your sources in a file, e.g. `sources.txt`:

   ```
   # Example sources file
   https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts
   ./local-list.txt
   ```

   - Lines starting with `#` are ignored.
   - Blank lines are ignored.

2. Run the script:

   ```bash
   chmod +x consolidate-pihole.sh
   ./consolidate-pihole.sh sources.txt consolidated-hosts.txt
   ```

3. The script will:
   - Fetch/copy each list
   - Extract valid domains
   - Remove duplicates
   - Save the result to `consolidated-hosts.txt`

4. Example output (first lines):

   ```
   # Consolidated Pi-hole hosts generated on 2025-10-11T12:00:00Z
   # Sources:
   # https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts
   # ./local-list.txt
   0.0.0.0 academiaeib.com
   0.0.0.0 academiajo.com
   0.0.0.0 academia-master.com
   ```

## Notes
- If you prefer a plain **domains-only** file, you can edit the last `awk` line in the script to just output the domains (remove the `0.0.0.0` prefix).
- Warnings will be printed if a list cannot be fetched or found, but the script will continue with the remaining sources.

## License
MIT
