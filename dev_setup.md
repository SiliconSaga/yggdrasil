# Development Environment Setup

This guide details how to set up the development environment for the **Yggdrasil** project.

## Windows Setup

We recommend using **Chocolatey** and **pyenv-win** to manage tools and Python versions. This approach avoids cluttering the system registry and provides a "Unix-like" consistency.

### Install Package Manager (Chocolatey)

Run the following in an **Administrator** PowerShell to install Chocolatey:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
```

### Install Core Tools

Once Chocolatey is installed, use it to install Git and the Python version manager:

```powershell
choco install git pyenv-win -y
```

> **Note**: You may need to restart your terminal after this step for the `pyenv` and `git` commands to be recognized.

### 3. Configure Python (via pyenv)

We use `pyenv` to ensure all developers use the same Python version (Target: **3.11.x**).

#### Install Python

```powershell
# Update pyenv first to ensure latest versions are available
pyenv update

# Install the target version
pyenv install 3.11.11

# Set it as global (or local to this repo)
pyenv global 3.11.11
```

### Verify Installation

```powershell
python --version
# Should output Python 3.11.11
```

### Shell Environment 

This is particularly crucial for Nordri

Many automation scripts (e.g., `bootstrap.sh`) are written in **Bash**. PowerShell and CMD cannot execute these scripts directly.

*   **Requirement**: You **MUST** use a Bash-compatible shell to run bootstrap and maintenance scripts.
*   **Recommendation**: Use **Git Bash** (installed automatically with Git).
*   **Recommendation**: Use the **Git Bash** application specifically.
*   **How to use**: Right-click in your project folder and select "Open Git Bash here".

> **Critical Warning**: Windows has a built-in `bash.exe` (executing WSL) in its system path.
> *   Typing `bash` in PowerShell/CMD will trigger this WSL instance (often failing if unconfigured).
> *   Even if you `cd` into `C:\Program Files\Git\bin`, typing `bash` will **STILL** execute the system one due to path precedence.
> *   You must use `.\bash` if you are in the directory, or better yet, use the **Git Bash** terminal which sets the paths correctly.

#### Understanding "Loki" and the Node
Your terminal prompt `cerva@Loki` indicates you are on your **Windows Host** (named Loki).
*   **The User**: `cerva`
*   **The Host**: `Loki` (Your Windows Machine)
*   **The Cluster**: `loki` (Your K3s Node Name)
*   **The VM**: Rancher runs a hidden VM (usually `rancher-desktop`) in the background.

When you run `bootstrap.sh` on **Loki** (Windows via Git Bash), it talks to the **Cluster** (in the VM) via `kubectl`. This is the correct remote-management architecture. You do *not* need to be "inside" the VM to bootstrap it.

### Kubernetes Prerequisites


For Nordri development on Windows, we suggest **Rancher Desktop**

*   **K3s Binary**: Note that when using Rancher Desktop, the `k3s` binary exists *inside* the virtual machine. It is **normal** that `k3s --version` fails in your Windows terminal. You only need `kubectl` (which Rancher installs) to interact with the cluster.

If you need _additional_ k3s clusters beyond the one provided by Rancher Desktop, you could install the full `k3d` environment that works via Docker and manage multiple clusters that way.

### PowerShell Quirks & Troubleshooting

PowerShell's default security settings can sometimes block `pyenv` scripts.

*   **Execution Policy Error**: If you see "cannot be loaded because running scripts is disabled", allow scripts for the current process:
    ```powershell
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process
    ```

*   **Outdated Version List**: If `pyenv install --list` shows only old versions (e.g., stopping at 3.11.0a), your local pyenv definitions are stale. Update them manually:
    ```powershell
    # Navigate to the pyenv-win directory
    cd $env:USERPROFILE\.pyenv\pyenv-win
    
    # Ensure you are on the master branch (fix detached head state)
    git checkout master
    
    # Pull latest changes
    git pull
    ```

*   **"Python was not found" / Microsoft Store opens**:
    If running `python` opens the Microsoft Store or says "Python was not found" despite successful installation:
    1.  Go to Windows Settings > Apps > Advanced app settings > **App execution aliases**.
    2.  Toggle **OFF** the entries for `python.exe` and `python3.exe`.

---

## macOS Setup (Coming Soon)

## Linux Setup (Coming Soon)
