# Git & GitHub Setup Guide for AutoDelete

A beginner-friendly guide to getting your addon on GitHub.

---

## Part 1: One-Time Setup

### 1.1 Install Git

**Windows:**
Download from https://git-scm.com/download/win and run the installer.
Use all the default options — they're fine.

**Mac:**
Open Terminal and type:
```
git --version
```
It will prompt you to install if it's not there.

### 1.2 Create a GitHub Account

Go to https://github.com and sign up (free).

### 1.3 Tell Git Who You Are

Open a terminal (or "Git Bash" on Windows) and run:
```
git config --global user.name "YourName"
git config --global user.email "your-email@example.com"
```
Use the same email you signed up to GitHub with.

---

## Part 2: Create Your Repository

### 2.1 Create the Repo on GitHub

1. Go to https://github.com/new
2. Repository name: `AutoDelete`
3. Description: `WoW 3.3.5 addon that auto-deletes specified items from your bags`
4. Choose **Public** (so others can find it) or **Private** (just for you)
5. **Do NOT** check "Add a README" (we already have one)
6. Click **Create repository**

GitHub will show you a page with setup instructions. Keep it open.

### 2.2 Initialize Git in Your Addon Folder

Open a terminal and navigate to your AutoDelete folder:
```
cd "C:/path/to/your/Interface/AddOns/AutoDelete"
```
Or wherever you keep the working copy. Then run:

```
git init
```
This creates a hidden `.git` folder — your addon is now a Git repository.

### 2.3 Connect to GitHub

Copy the URL from your GitHub repo page (it looks like `https://github.com/YourName/AutoDelete.git`) and run:
```
git remote add origin https://github.com/YourName/AutoDelete.git
```
This tells Git where to push your code.

### 2.4 Add All Your Files

```
git add .
```
The `.` means "everything in this folder." Git is now tracking all your files.

### 2.5 Make Your First Commit

```
git commit -m "Initial release v1.2.0"
```
A commit is like a save point. The `-m` flag is your message describing what changed.

### 2.6 Push to GitHub

```
git branch -M main
git push -u origin main
```
The first time you push, GitHub will ask you to log in. After this, your code is live on GitHub!

---

## Part 3: Day-to-Day Workflow

This is what you'll do every time you make changes.

### The 3-Step Loop

After editing your files:

```
git add .                          # Stage all changes
git commit -m "describe what changed"   # Save a snapshot
git push                           # Upload to GitHub
```

That's it. Those 3 commands are 90% of Git.

### Good Commit Messages

Keep them short and descriptive:
```
git commit -m "Add auto-delete gray items feature"
git commit -m "Fix dropdown not updating after profile switch"
git commit -m "Restyle all borders to thin ElvUI look"
git commit -m "Update README with ElvUI instructions"
```

Bad messages: "stuff", "update", "fix", "asdf"

### Check What's Changed

Before committing, you can see what you've modified:
```
git status              # Shows which files changed
git diff                # Shows the actual line-by-line changes
git diff Options.lua    # Shows changes in one specific file
```

### View Your History

```
git log --oneline       # Short list of all commits
git log                 # Detailed list with dates and messages
```

---

## Part 4: Releases & Tags

When you ship a version, tag it so people can find specific releases.

### Create a Tag

```
git tag -a v1.2.0 -m "ElvUI drop targets, auto-gray items, restyled UI"
git push origin v1.2.0
```

### Create a GitHub Release

1. Go to your repo on GitHub
2. Click **Releases** (right side)
3. Click **Create a new release**
4. Choose your tag (v1.2.0)
5. Title: `v1.2.0 - ElvUI Integration & Auto-Gray Items`
6. Description: paste the relevant section from CHANGELOG.md
7. Optionally attach a .zip of the addon folder
8. Click **Publish release**

---

## Part 5: Useful Extras

### Undo Your Last Commit (before pushing)

Made a mistake? Undo the last commit but keep your changes:
```
git reset --soft HEAD~1
```

### Ignore Mistakes Already Committed

If you accidentally committed a file you shouldn't have:
```
git rm --cached filename.txt
git commit -m "Remove accidentally committed file"
```

### See What a Past Version Looked Like

```
git log --oneline       # Find the commit hash (e.g., a1b2c3d)
git show a1b2c3d        # See what changed in that commit
```

### Clone Your Repo on Another Computer

```
git clone https://github.com/YourName/AutoDelete.git
```

---

## Quick Reference Card

| What you want to do | Command |
|---|---|
| Start a new repo | `git init` |
| Stage changes | `git add .` |
| Commit | `git commit -m "message"` |
| Push to GitHub | `git push` |
| Pull latest from GitHub | `git pull` |
| Check status | `git status` |
| View history | `git log --oneline` |
| Create a version tag | `git tag -a v1.0.0 -m "description"` |
| Push a tag | `git push origin v1.0.0` |
| Clone a repo | `git clone <url>` |

---

## Typical Session Example

```bash
# You just finished adding a new feature
cd "C:/WoW/Interface/AddOns/AutoDelete"

git status
# Shows: modified AutoDelete.lua, modified Options.lua

git add .
git commit -m "Add item quality filter to options panel"
git push

# Ready to release?
git tag -a v1.3.0 -m "Item quality filter"
git push origin v1.3.0
# Then go to GitHub and create a Release
```
