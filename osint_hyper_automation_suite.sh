#!/bin/bash

# OSINT Hyper Automation Suite v4.0
# Author: Black Hat Assistant
# License: MIT

# Global Configuration
CONFIG_FILE="./osint_config.conf"
LOG_DIR="./logs"
REPORTS_DIR="./reports"
TOOL_DIR="/opt/OSINT_Elite"
THREADS=10
GOPATH="$HOME/go"
PATH="$PATH:$GOPATH/bin"

# Color Scheme
COLOR_SUCCESS="\033[38;5;40m"
COLOR_WARNING="\033[38;5;214m"
COLOR_ERROR="\033[38;5;196m"
COLOR_HEADER="\033[38;5;27m"
COLOR_RESET="\033[0m"

# Initialize directories
init_directories() {
    mkdir -p "$LOG_DIR" "$REPORTS_DIR" "$TOOL_DIR"
    touch "$LOG_DIR/install.log" "$LOG_DIR/scan.log"
}

# Load configuration
load_config() {
    [ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"
}

# Cleanup function
quantum_cleanup() {
    echo -e "${COLOR_WARNING}Cleaning up resources...${COLOR_RESET}"
    pkill -P $$  # Kill child processes
    rm -rf temp_*
}

# Show banner
show_banner() {
    clear
    echo -e "${COLOR_HEADER}"
    echo " ██████╗ ███████╗██╗███╗   ██╗████████╗"
    echo "██╔═══██╗██╔════╝██║████╗  ██║╚══██╔══╝"
    echo "██║   ██║███████╗██║██╔██╗ ██║   ██║   "
    echo "██║   ██║╚════██║██║██║╚██╗██║   ██║   "
    echo "╚██████╔╝███████║██║██║ ╚████║   ██║   "
    echo " ╚═════╝ ╚══════╝╚═╝╚═╝  ╚═══╝   ╚═╝   "
    echo -e "${COLOR_RESET}"
}

# Core Installation Function
install_required_tools() {
    echo -e "${COLOR_HEADER}=== INSTALLING CORE DEPENDENCIES ===${COLOR_RESET}"
    
    # System Update
    sudo apt-get update -y
    sudo apt-get upgrade -y
    
    # Base System Packages
    SYSTEM_DEPS=(
        git curl wget jq
        python3 python3-pip python3-venv
        golang-go libssl-dev
        nmap masscan dnsutils
        libxml2 libxslt1-dev zlib1g-dev
        ruby ruby-dev build-essential
        chromium
    )
    
    echo -e "${COLOR_SUCCESS}Installing system dependencies...${COLOR_RESET}"
    sudo apt-get install -y "${SYSTEM_DEPS[@]}" 2>&1 | tee "$LOG_DIR/install.log"
    
    # Python Environment Setup
    echo -e "${COLOR_SUCCESS}Configuring Python environment...${COLOR_RESET}"
    python3 -m venv "$TOOL_DIR/venv"
    source "$TOOL_DIR/venv/bin/activate"
    
    PYTHON_DEPS=(
        tensorflow keras numpy pandas
        plotly matplotlib selenium
        scrapy python-nmap requests
        bs4 lxml django
    )
    
    echo -e "${COLOR_SUCCESS}Installing Python packages...${COLOR_RESET}"
    pip3 install --upgrade pip wheel
    pip3 install "${PYTHON_DEPS[@]}" 2>&1 | tee -a "$LOG_DIR/install.log"
    deactivate
    
    # Go Tools Installation
    echo -e "${COLOR_SUCCESS}Installing Go tools...${COLOR_RESET}"
    GO_TOOLS=(
        "github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest"
        "github.com/projectdiscovery/httpx/cmd/httpx@latest"
        "github.com/projectdiscovery/nuclei/v2/cmd/nuclei@latest"
        "github.com/ffuf/ffuf@latest"
        "github.com/tomnomnom/waybackurls@latest"
        "github.com/tomnomnom/assetfinder@latest"
    )
    
    for tool in "${GO_TOOLS[@]}"; do
        echo -e "${COLOR_SUCCESS}Installing $tool...${COLOR_RESET}"
        go install "$tool" 2>&1 | tee -a "$LOG_DIR/install.log"
    done
    
    # Ruby Gems
    echo -e "${COLOR_SUCCESS}Installing Ruby gems...${COLOR_RESET}"
    sudo gem install wpscan whatweb 2>&1 | tee -a "$LOG_DIR/install.log"
    
    # Node.js Tools
    if ! command -v npm &> /dev/null; then
        curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
        sudo apt-get install -y nodejs
    fi
    sudo npm install -g wappalyzer 2>&1 | tee -a "$LOG_DIR/install.log"
    
    # Custom Tools from Source
    echo -e "${COLOR_SUCCESS}Cloning security repositories...${COLOR_RESET}"
    REPOS=(
        "https://github.com/aboul3la/Sublist3r.git"
        "https://github.com/maurosoria/dirsearch.git"
        "https://github.com/EnableSecurity/wafw00f.git"
    )
    
    for repo in "${REPOS[@]}"; do
        repo_name=$(basename "$repo" .git)
        if [ ! -d "$TOOL_DIR/$repo_name" ]; then
            git clone "$repo" "$TOOL_DIR/$repo_name" 2>&1 | tee -a "$LOG_DIR/install.log"
            if [ -f "$TOOL_DIR/$repo_name/setup.py" ]; then
                (cd "$TOOL_DIR/$repo_name" && python3 setup.py install) 2>&1 | tee -a "$LOG_DIR/install.log"
            fi
        fi
    done
    
    echo -e "${COLOR_SUCCESS}All dependencies installed successfully!${COLOR_RESET}"
}

# Scanning Function
neural_scan() {
    local target=$1
    echo -e "${COLOR_HEADER}Starting scan of $target...${COLOR_RESET}"
    
    # Create scan directory
    local scan_dir="$REPORTS_DIR/$target-$(date +%Y%m%d%H%M)"
    mkdir -p "$scan_dir"
    
    # Subdomain enumeration
    echo -e "${COLOR_SUCCESS}Running subdomain discovery...${COLOR_RESET}"
    subfinder -d "$target" -silent -o "$scan_dir/subdomains.txt" 2>&1 | tee "$scan_dir/scan.log"
    
    # Live host verification
    echo -e "${COLOR_SUCCESS}Checking live hosts...${COLOR_RESET}"
    httpx -l "$scan_dir/subdomains.txt" -silent -status-code -title -o "$scan_dir/live_hosts.txt" 2>&1 | tee -a "$scan_dir/scan.log"
    
    # Vulnerability scanning
    echo -e "${COLOR_SUCCESS}Running vulnerability checks...${COLOR_RESET}"
    nuclei -l "$scan_dir/live_hosts.txt" -t ~/nuclei-templates/ -o "$scan_dir/vulnerabilities.txt" 2>&1 | tee -a "$scan_dir/scan.log"
    
    generate_report "$target" "$scan_dir"
}

# Report Generation
generate_report() {
    local target=$1
    local scan_dir=$2
    
    echo -e "${COLOR_HEADER}Generating HTML report...${COLOR_RESET}"
    
    cat << EOF > "$scan_dir/report.html"
<!DOCTYPE html>
<html>
<head>
    <title>OSINT Report - $target</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 2em; }
        h1 { color: #2c3e50; }
        .section { margin-bottom: 2em; }
        pre { background: #f4f4f4; padding: 1em; overflow-x: auto; }
        table { width: 100%; border-collapse: collapse; }
        th, td { padding: 0.5em; border: 1px solid #ddd; }
    </style>
</head>
<body>
    <h1>OSINT Report for $target</h1>
    <p>Generated: $(date)</p>
    
    <div class="section">
        <h2>Subdomains ($(wc -l < "$scan_dir/subdomains.txt"))</h2>
        <pre>$(cat "$scan_dir/subdomains.txt")</pre>
    </div>
    
    <div class="section">
        <h2>Live Hosts ($(wc -l < "$scan_dir/live_hosts.txt"))</h2>
        <pre>$(awk '{print $1}' "$scan_dir/live_hosts.txt")</pre>
    </div>
    
    <div class="section">
        <h2>Vulnerabilities</h2>
        <table>
            <tr><th>Severity</th><th>Vulnerability</th><th>Host</th></tr>
            $(awk -F' ' '{print "<tr><td>"$1"</td><td>"$2"</td><td>"$3"</td></tr>"}' "$scan_dir/vulnerabilities.txt")
        </table>
    </div>
</body>
</html>
EOF

    echo -e "${COLOR_SUCCESS}Report generated: $scan_dir/report.html${COLOR_RESET}"
}

# Interactive Menu
interactive_menu() {
    PS3='Choose an option: '
    options=("Install Tools" "Run Scan" "Generate Report" "Exit")
    
    select opt in "${options[@]}"; do
        case $opt in
            "Install Tools")
                install_required_tools
                ;;
            "Run Scan")
                read -p "Enter target domain: " target
                neural_scan "$target"
                ;;
            "Generate Report")
                read -p "Enter scan directory: " scan_dir
                generate_report "$(basename "$scan_dir")" "$scan_dir"
                ;;
            "Exit")
                exit 0
                ;;
            *) 
                echo -e "${COLOR_ERROR}Invalid option${COLOR_RESET}"
                ;;
        esac
    done
}

# Main Execution
main() {
    trap "quantum_cleanup" EXIT
    init_directories
    load_config
    show_banner
    interactive_menu
}

# Start main execution
main "$@"
