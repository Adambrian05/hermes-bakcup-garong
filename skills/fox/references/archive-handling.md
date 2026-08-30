# Archive Handling & Bulk Skill Merge

## Download from Google Drive

```bash
pip3 install gdown

# Download file
gdown "https://drive.google.com/uc?id=FILE_ID" -O output.zip
```

## Verify File Type

```bash
# Check actual file type (may differ from extension!)
file output.zip

# Common: .zip extension but actually RAR
# output.zip: RAR archive data, v5
```

## Extract RAR

```bash
apt-get install -y unrar

# List contents
unrar l archive.rar

# Extract
unrar x -o+ archive.rar /destination/
```

## Extract ZIP

```bash
# List contents
unzip -l archive.zip

# Extract
unzip -o archive.zip -d /destination/
```

## Bulk Skill Merge

When receiving archive with Hermes-compatible skills:

```bash
# Extract to temp
unzip -o archive.zip -d /tmp/skills_temp/

# Copy skills
cp -r /tmp/skills_temp/skills/* /root/.hermes/skills/

# Copy scripts
cp -r /tmp/skills_temp/tools/* /root/.hermes/scripts/
```

## Verify Merge

```bash
ls -la /root/.hermes/skills/
ls -la /root/.hermes/scripts/
```

## Pitfalls

1. **File extension mismatch**: Always verify with `file` command — .zip may contain RAR
2. **Google Drive**: Use `gdown` not `wget` — requires auth bypass
3. **Skill format**: Skills need SKILL.md + proper directory structure to be recognized by Hermes
4. **Duplicate overwrites**: `cp -r` overwrites existing files silently
