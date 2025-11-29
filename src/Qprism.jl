#!/usr/bin/env julia
#┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
#┃ 📁File      📄 Qprism.jl                                                          ┃
#┃ 📙Brief     📝 Volvo Supplier Quality Notification System                         ┃
#┃ 🧾Details   🔎 Web scraping, dashboard generation, and email notifications        ┃
#┃ 🚩OAuthor   🦋 Original Author: Jaewoo Joung/정재우/郑在祐                         ┃
#┃ 👨‍🔧LAuthor   👤 Last Author: Jaewoo Joung                                         ┃
#┃ 📆LastDate  📍 2025-11-29 🔄Please support to keep update🔄                       ┃
#┃ 🏭License   📜 JSD:Just Simple Distribution(Jaewoo's Simple Distribution)         ┃
#┃ ✅Guarantee ⚠️ Explicitly UN-guaranteed                                           ┃
#┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

module Qprism

using WebDriver
using Gumbo
using Cascadia
using JSON3
using Dates
using Printf
using AbstractTrees
using TOML
using HTTP
using Sendmail

export qprismrun

#= ═══════════════════════════════════════════════════════════════════════════════════
   CONSTANTS & CONFIGURATION
   ═══════════════════════════════════════════════════════════════════════════════════ =#

const VSIB_BASE_URL = "https://vsib.srv.volvo.com"
const SCORECARD_URL = "https://vsib.srv.volvo.com/vsib/Content/sus/SupplierScorecard.aspx"
const REQUEST_DELAY = 2
const PAGE_LOAD_TIMEOUT = 60
const DEFAULT_WEBDRIVER_PORT = 9515

#= Remote config URLs =#
const CONFIG_URLS = Dict(
    "config.toml" => "https://jaewoojoung.github.io/volv/conf/config.toml",
    "suppliers.toml" => "https://jaewoojoung.github.io/volv/conf/suppliers.toml",
    "index.html" => "https://jaewoojoung.github.io/volv/temp/index.html",
    "supplier.html" => "https://jaewoojoung.github.io/volv/temp/supplier.html"
)

#= ═══════════════════════════════════════════════════════════════════════════════════
   INITIALIZATION - Download config files if missing
   ═══════════════════════════════════════════════════════════════════════════════════ =#

#= get_workspace_dir()
   Get or create the QPrism workspace directory in user's home. =#
function get_workspace_dir()
    if Sys.iswindows()
        base = get(ENV, "USERPROFILE", homedir())
    else
        base = homedir()
    end
    workspace = joinpath(base, ".qprism")
    mkpath(workspace)
    return workspace
end

#= init_workspace()
   Initialize workspace by creating directories and downloading config files if missing. =#
function init_workspace()
    workspace = get_workspace_dir()
    
    #= Create subdirectories =#
    for dir in ["conf", "temp", "data", "dashboard", "dashboard/suppliers"]
        dir_path = joinpath(workspace, dir)
        if !isdir(dir_path)
            mkpath(dir_path)
            println("📁 Created: $dir/")
        end
    end
    
    #= Download config files if missing =#
    files_to_download = [
        ("conf/config.toml", CONFIG_URLS["config.toml"]),
        ("conf/suppliers.toml", CONFIG_URLS["suppliers.toml"]),
        ("temp/index.html", CONFIG_URLS["index.html"]),
        ("temp/supplier.html", CONFIG_URLS["supplier.html"])
    ]
    
    for (local_path, url) in files_to_download
        full_path = joinpath(workspace, local_path)
        if !isfile(full_path)
            println("⬇️  Downloading: $local_path")
            try
                response = HTTP.get(url; status_exception=false)
                if response.status == 200
                    open(full_path, "w") do f
                        write(f, String(response.body))
                    end
                    println("   ✓ Downloaded: $local_path")
                else
                    println("   ⚠️  HTTP $(response.status) - creating default")
                    create_default_file(full_path, local_path)
                end
            catch e
                println("   ⚠️  Failed to download: $e")
                create_default_file(full_path, local_path)
            end
        end
    end
    
    println("\n📂 Workspace: $workspace")
    return workspace
end

#= create_default_file(path, filename)
   Create default config file if download fails. =#
function create_default_file(path, filename)
    if occursin("suppliers.toml", filename)
        content = """
# ═══════════════════════════════════════════════════════════════════════════════════
# QPrism Supplier Configuration
# ═══════════════════════════════════════════════════════════════════════════════════

[[suppliers]]
# Add your PARMA codes here (comma-separated integers)
# parma_codes = [32731, 33568]
parma_codes = []

[myemail]
# Add your email address for notifications
# myemail = "jaewoo.joung@consultant.volvo.com"
myemail = ""
"""
        open(path, "w") do f
            write(f, content)
        end
        println("   📝 Created default: $filename")
    elseif occursin("config.toml", filename)
        content = """
# ═══════════════════════════════════════════════════════════════════════════════════
# QPrism SMTP Configuration
# ═══════════════════════════════════════════════════════════════════════════════════

[smtp]
server = "smtp.gmail.com"
port = 587
username = ""
password = ""
"""
        open(path, "w") do f
            write(f, content)
        end
        println("   📝 Created default: $filename")
    elseif occursin("index.html", filename)
        open(path, "w") do f
            write(f, get_default_index_template())
        end
        println("   📝 Created default: $filename")
    elseif occursin("supplier.html", filename)
        open(path, "w") do f
            write(f, get_default_supplier_template())
        end
        println("   📝 Created default: $filename")
    end
end

#= ═══════════════════════════════════════════════════════════════════════════════════
   DEFAULT TEMPLATES (embedded)
   ═══════════════════════════════════════════════════════════════════════════════════ =#

function get_default_index_template()
    return """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>QPrism - Supplier Quality Dashboard</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: 'Segoe UI', Tahoma, sans-serif; background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%); min-height: 100vh; color: #fff; }
        .header { background: rgba(255,255,255,0.1); backdrop-filter: blur(10px); padding: 20px 40px; display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid rgba(255,255,255,0.1); }
        .logo { font-size: 28px; font-weight: 700; color: #00d4ff; }
        .logo span { color: #fff; }
        .stats { display: flex; gap: 30px; }
        .stat { text-align: center; }
        .stat-value { font-size: 24px; font-weight: 700; color: #00d4ff; }
        .stat-label { font-size: 12px; color: rgba(255,255,255,0.6); text-transform: uppercase; }
        .container { max-width: 1400px; margin: 0 auto; padding: 40px; }
        .title { font-size: 32px; margin-bottom: 30px; }
        .suppliers-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(320px, 1fr)); gap: 20px; }
        .supplier-card { background: rgba(255,255,255,0.05); border-radius: 16px; padding: 24px; border: 1px solid rgba(255,255,255,0.1); cursor: pointer; transition: all 0.3s ease; }
        .supplier-card:hover { background: rgba(255,255,255,0.1); transform: translateY(-4px); box-shadow: 0 20px 40px rgba(0,0,0,0.3); }
        .supplier-card h3 { font-size: 18px; margin-bottom: 8px; }
        .supplier-card .parma { font-size: 14px; color: rgba(255,255,255,0.6); margin-bottom: 16px; }
        .metrics-row { display: flex; gap: 12px; flex-wrap: wrap; }
        .metrics-row span { padding: 6px 12px; border-radius: 20px; font-size: 12px; font-weight: 600; }
        .status-approved { background: rgba(46,204,113,0.2); color: #2ecc71; }
        .status-expired { background: rgba(231,76,60,0.2); color: #e74c3c; }
        .status-na { background: rgba(149,165,166,0.2); color: #95a5a6; }
        .trend-up { background: rgba(231,76,60,0.2); color: #e74c3c; }
        .trend-down { background: rgba(46,204,113,0.2); color: #2ecc71; }
        .trend-neutral { background: rgba(241,196,15,0.2); color: #f1c40f; }
        .footer { text-align: center; padding: 40px; color: rgba(255,255,255,0.4); font-size: 14px; }
    </style>
</head>
<body>
    <div class="header">
        <div class="logo">Q<span>Prism</span></div>
        <div class="stats"><div class="stat"><div class="stat-value">{{TOTAL_SUPPLIERS}}</div><div class="stat-label">Suppliers</div></div></div>
    </div>
    <div class="container">
        <h1 class="title">Supplier Quality Dashboard</h1>
        <div class="suppliers-grid">{{SUPPLIER_CARDS}}</div>
    </div>
    <div class="footer">Generated: {{GENERATED_DATE}} | QPrism - Volvo Supplier Quality System</div>
</body>
</html>
"""
end

function get_default_supplier_template()
    return """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{{SUPPLIER_NAME}} - QPrism</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: 'Segoe UI', Tahoma, sans-serif; background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%); min-height: 100vh; color: #fff; }
        .header { background: rgba(255,255,255,0.1); backdrop-filter: blur(10px); padding: 20px 40px; display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid rgba(255,255,255,0.1); }
        .logo { font-size: 28px; font-weight: 700; color: #00d4ff; }
        .logo span { color: #fff; }
        .back-link { color: #00d4ff; text-decoration: none; }
        .back-link:hover { text-decoration: underline; }
        .container { max-width: 1200px; margin: 0 auto; padding: 40px; }
        .supplier-header { display: flex; align-items: center; gap: 24px; margin-bottom: 40px; }
        .supplier-logo { width: 80px; height: 80px; border-radius: 12px; background: rgba(255,255,255,0.1); object-fit: contain; }
        .supplier-info h1 { font-size: 32px; margin-bottom: 8px; }
        .supplier-info .parma { font-size: 16px; color: rgba(255,255,255,0.6); }
        .cards-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 24px; margin-bottom: 40px; }
        .card { background: rgba(255,255,255,0.05); border-radius: 16px; padding: 24px; border: 1px solid rgba(255,255,255,0.1); }
        .card h2 { font-size: 18px; margin-bottom: 20px; color: #00d4ff; }
        .metric-row { display: flex; justify-content: space-between; align-items: center; padding: 12px 0; border-bottom: 1px solid rgba(255,255,255,0.1); }
        .metric-row:last-child { border-bottom: none; }
        .metric-label { color: rgba(255,255,255,0.6); }
        .metric-value { font-weight: 600; }
        .status-approved { color: #2ecc71; }
        .status-expired { color: #e74c3c; }
        .status-na { color: #95a5a6; }
        .trend-up { color: #e74c3c; }
        .trend-down { color: #2ecc71; }
        .trend-neutral { color: #f1c40f; }
        table { width: 100%; border-collapse: collapse; }
        table th, table td { padding: 12px; text-align: left; border-bottom: 1px solid rgba(255,255,255,0.1); }
        table th { color: rgba(255,255,255,0.6); font-weight: 500; }
        .full-width { grid-column: 1 / -1; }
        .footer { text-align: center; padding: 40px; color: rgba(255,255,255,0.4); font-size: 14px; }
        .vsib-link { display: inline-block; margin-top: 10px; padding: 10px 20px; background: #00d4ff; color: #1a1a2e; text-decoration: none; border-radius: 8px; font-weight: 600; }
        .vsib-link:hover { background: #00b8e6; }
    </style>
</head>
<body>
    <div class="header">
        <div class="logo">Q<span>Prism</span></div>
        <a href="index.html" class="back-link">← Back to Dashboard</a>
    </div>
    <div class="container">
        <div class="supplier-header">
            <img src="{{SUPPLIER_LOGO}}" alt="" class="supplier-logo" onerror="this.style.display='none'">
            <div class="supplier-info">
                <h1>{{SUPPLIER_NAME}}</h1>
                <p class="parma">PARMA: {{PARMA_ID}}</p>
                <a href="https://vsib.srv.volvo.com/vsib/Content/sus/SupplierScorecard.aspx?SupplierId={{PARMA_ID}}" target="_blank" class="vsib-link">View in VSIB →</a>
            </div>
        </div>
        <div class="cards-grid">
            <div class="card"><h2>Project Status</h2><div class="metric-row"><span class="metric-label">APQP</span><span class="metric-value">{{APQP}}</span></div><div class="metric-row"><span class="metric-label">PPAP</span><span class="metric-value">{{PPAP}}</span></div></div>
            <div class="card"><h2>Software Index</h2><div class="metric-row"><span class="metric-label">Index</span><span class="metric-value">{{SW_INDEX}}</span></div><div class="metric-row"><span class="metric-label">Status</span><span class="metric-value {{SW_CLASS}}">{{SW_STATUS}}</span></div><div class="metric-row"><span class="metric-label">Audit Date</span><span class="metric-value">{{SW_DATE}}</span></div></div>
            <div class="card"><h2>EE Index</h2><div class="metric-row"><span class="metric-label">Index</span><span class="metric-value">{{EE_INDEX}}</span></div><div class="metric-row"><span class="metric-label">Status</span><span class="metric-value {{EE_CLASS}}">{{EE_STATUS}}</span></div><div class="metric-row"><span class="metric-label">Audit Date</span><span class="metric-value">{{EE_DATE}}</span></div></div>
            <div class="card"><h2>SMA / Criticality 1</h2><div class="metric-row"><span class="metric-label">Index</span><span class="metric-value">{{SMA}}</span></div><div class="metric-row"><span class="metric-label">Status</span><span class="metric-value">{{SMA_STATUS}}</span></div><div class="metric-row"><span class="metric-label">Audit Date</span><span class="metric-value">{{SMA_DATE}}</span></div></div>
            <div class="card"><h2>QPM Performance</h2><div class="metric-row"><span class="metric-label">Last Period</span><span class="metric-value">{{QPM_LAST}}</span></div><div class="metric-row"><span class="metric-label">Actual</span><span class="metric-value {{QPM_CLASS}}">{{QPM_ACTUAL}}</span></div><div class="metric-row"><span class="metric-label">Change</span><span class="metric-value {{QPM_CLASS}}">{{QPM_CHANGE}}</span></div></div>
            <div class="card"><h2>PPM Performance</h2><div class="metric-row"><span class="metric-label">Last Period</span><span class="metric-value">{{PPM_LAST}}</span></div><div class="metric-row"><span class="metric-label">Actual</span><span class="metric-value {{PPM_CLASS}}">{{PPM_ACTUAL}}</span></div><div class="metric-row"><span class="metric-label">Change</span><span class="metric-value {{PPM_CLASS}}">{{PPM_CHANGE}}</span></div></div>
            <div class="card full-width"><h2>Certifications</h2><table><thead><tr><th>Certification</th><th>Certified Place</th><th>Expiry Date</th><th>Status</th></tr></thead><tbody>{{CERTIFICATIONS_HTML}}</tbody></table></div>
        </div>
    </div>
    <div class="footer">Generated: {{GENERATED_DATE}} | QPrism - Volvo Supplier Quality System</div>
</body>
</html>
"""
end

#= ═══════════════════════════════════════════════════════════════════════════════════
   SUPPLIER DATA LOADING
   ═══════════════════════════════════════════════════════════════════════════════════ =#

#= load_suppliers_config(workspace)
   Load PARMA codes and email from suppliers.toml =#
function load_suppliers_config(workspace::String)
    config_path = joinpath(workspace, "conf", "suppliers.toml")
    
    if !isfile(config_path)
        println("❌ suppliers.toml not found at: $config_path")
        return nothing, nothing
    end
    
    try
        data = TOML.parsefile(config_path)
        
        #= Extract PARMA codes =#
        parma_codes = Int[]
        for supplier in get(data, "suppliers", [])
            codes = get(supplier, "parma_codes", Int[])
            append!(parma_codes, codes)
        end
        parma_codes = unique(parma_codes)
        
        #= Extract email =#
        myemail_section = get(data, "myemail", Dict())
        myemail = get(myemail_section, "myemail", "")
        
        if isempty(parma_codes)
            println("⚠️  No PARMA codes found in suppliers.toml")
            println("   Please edit: $config_path")
        else
            println("📋 Loaded $(length(parma_codes)) PARMA codes: $(join(parma_codes, ", "))")
        end
        
        if isempty(myemail)
            println("⚠️  No email configured in suppliers.toml")
        else
            println("📧 Email: $myemail")
        end
        
        return parma_codes, myemail
        
    catch e
        println("❌ Error reading suppliers.toml: $e")
        return nothing, nothing
    end
end

#= ═══════════════════════════════════════════════════════════════════════════════════
   CHROMEDRIVER MANAGEMENT
   ═══════════════════════════════════════════════════════════════════════════════════ =#

#= launch_chromedriver(; port)
   Launch ChromeDriver as background process. =#
function launch_chromedriver(; port::Int = DEFAULT_WEBDRIVER_PORT)::Bool
    println("🚀 Launching ChromeDriver on port $port...")
    
    try
        if Sys.iswindows()
            cmd_str = "start /B chromedriver --port=$port --log-level=OFF 2>NUL"
            run(Cmd(`cmd /c $cmd_str`, ignorestatus=true), wait=false)
        else
            cmd = `chromedriver --port=$port --log-level=OFF`
            run(pipeline(cmd, stdout=devnull, stderr=devnull), wait=false)
        end
        
        println("⏳ Waiting for ChromeDriver...")
        sleep(3)
        
        #= Verify server =#
        for attempt in 1:3
            try
                capabilities = Capabilities("chrome")
                wd = RemoteWebDriver(capabilities, host="localhost", port=port)
                println("✅ ChromeDriver ready")
                return true
            catch
                attempt < 3 && sleep(2)
            end
        end
        
        return true
    catch e
        println("❌ ChromeDriver failed: $e")
        println("💡 Install ChromeDriver: https://chromedriver.chromium.org/downloads")
        return false
    end
end

#= terminate_chromedriver()
   Terminate ChromeDriver processes. =#
function terminate_chromedriver()
    try
        if Sys.iswindows()
            run(`cmd /c "taskkill /F /IM chromedriver.exe 2>nul"`, wait=true)
        else
            run(`pkill -f chromedriver`, wait=false)
        end
        println("🛑 ChromeDriver terminated")
    catch
    end
end

#= create_chrome_session(; port, headless)
   Create Chrome WebDriver session. =#
function create_chrome_session(; port::Int = DEFAULT_WEBDRIVER_PORT, headless::Bool = true)
    try
        chrome_args = [
            "--log-level=3", "--silent", "--disable-logging",
            "--disable-gpu-logging", "--disable-software-rasterizer",
            "--disable-background-networking", "--disable-sync",
            "--disable-translate", "--disable-default-apps",
            "--disable-extensions", "--no-first-run",
            "--disable-client-side-phishing-detection",
            "--disable-component-update", "--disable-infobars",
            "--disable-dev-shm-usage", "--no-sandbox"
        ]
        
        headless && push!(chrome_args, "--headless=new")
        
        chrome_options = Dict(
            "args" => chrome_args,
            "excludeSwitches" => ["enable-logging", "enable-automation"]
        )
        
        caps = Capabilities("chrome")
        caps.data["goog:chromeOptions"] = chrome_options
        
        wd = RemoteWebDriver(caps, host="localhost", port=port)
        session = Session(wd)
        
        println("✅ Chrome session created")
        return session
    catch e
        println("❌ Failed to create session: $e")
        return nothing
    end
end

#= ═══════════════════════════════════════════════════════════════════════════════════
   WEB SCRAPING
   ═══════════════════════════════════════════════════════════════════════════════════ =#

#= scrape_supplier(session, parma_code)
   Scrape supplier scorecard HTML. =#
function scrape_supplier(session, parma_code::Int)
    url = "$SCORECARD_URL?SupplierId=$parma_code"
    println("   🌐 Loading: $url")
    
    try
        navigate!(session, url)
        sleep(3)
        
        html = script!(session, "return document.documentElement.outerHTML;")
        
        if isnothing(html) || isempty(html)
            return nothing, "Empty response"
        end
        
        if occursin("login", lowercase(html)) || occursin("sign in", lowercase(html))
            return nothing, "Authentication required"
        end
        
        return html, nothing
        
    catch e
        return nothing, string(e)
    end
end

#= scrape_all_suppliers(workspace, parma_codes; headless)
   Scrape all suppliers and save HTML files. =#
function scrape_all_suppliers(workspace::String, parma_codes::Vector{Int}; headless::Bool = true)
    println("\n" * "="^60)
    println("📡 VSIB SUPPLIER SCRAPER")
    println("="^60)
    
    if isempty(parma_codes)
        println("❌ No PARMA codes to scrape")
        return 0
    end
    
    data_dir = joinpath(workspace, "data")
    mkpath(data_dir)
    
    if !launch_chromedriver()
        return 0
    end
    
    session = nothing
    successful = 0
    
    try
        session = create_chrome_session(headless=headless)
        if isnothing(session)
            return 0
        end
        
        for (i, parma) in enumerate(parma_codes)
            println("\n[$i/$(length(parma_codes))] Scraping PARMA: $parma")
            
            html, err = scrape_supplier(session, parma)
            
            if !isnothing(html)
                filename = joinpath(data_dir, "supplier_$parma.html")
                open(filename, "w") do f
                    write(f, html)
                end
                println("   ✅ Saved: supplier_$parma.html")
                successful += 1
            else
                println("   ❌ Failed: $err")
            end
            
            i < length(parma_codes) && sleep(REQUEST_DELAY)
        end
        
    finally
        !isnothing(session) && try delete!(session) catch end
        terminate_chromedriver()
    end
    
    println("\n📊 Scraped: $successful/$(length(parma_codes)) suppliers")
    return successful
end

#= ═══════════════════════════════════════════════════════════════════════════════════
   HTML PARSING
   ═══════════════════════════════════════════════════════════════════════════════════ =#

extract_text(elem) = isnothing(elem) ? "N/A" : (t = strip(nodeText(elem)); isempty(t) ? "N/A" : t)
get_attr(elem, attr::String) = isnothing(elem) ? "" : get(attrs(elem), attr, "")

#= parse_supplier_html(html_path)
   Parse supplier HTML file and extract data. =#
function parse_supplier_html(html_path::String)
    println("📄 Parsing: $(basename(html_path))")
    
    html_content = read(html_path, String)
    doc = parsehtml(html_content)
    
    data = Dict{String, Any}(
        "id" => "N/A", "parmaId" => "N/A", "name" => "Unknown", "logo" => "",
        "apqp" => "N/A", "ppap" => "N/A",
        "metrics" => Dict{String, Any}(),
        "qpm" => Dict("lastPeriod" => "N/A", "actual" => "N/A", "change" => "N/A", "trend" => "neutral"),
        "ppm" => Dict("lastPeriod" => "N/A", "actual" => "N/A", "change" => "N/A", "trend" => "neutral"),
        "audits" => [], "certifications" => []
    )
    
    #= Extract supplier info =#
    supplier_link = eachmatch(Selector("a[href*='SupplierInformation.aspx']"), doc.root)
    if !isempty(supplier_link)
        supplier_info = extract_text(first(supplier_link))
        if occursin(',', supplier_info)
            parts = split(supplier_info, ',', limit=2)
            data["id"] = strip(parts[1])
            data["parmaId"] = strip(parts[1])
            data["name"] = strip(parts[2])
        end
    end
    
    #= Extract logo =#
    logo_elem = eachmatch(Selector("#imgSupplierPhoto"), doc.root)
    !isempty(logo_elem) && (data["logo"] = get_attr(first(logo_elem), "src"))
    
    #= Extract APQP/PPAP =#
    apqp_elem = eachmatch(Selector("#lblApqpPpap"), doc.root)
    if !isempty(apqp_elem)
        apqp_text = extract_text(first(apqp_elem))
        m = match(r"APQP:\s*([^\s,]+)", apqp_text)
        !isnothing(m) && (data["apqp"] = m.captures[1])
        m = match(r"PPAP:\s*([^\s,]+)", apqp_text)
        !isnothing(m) && (data["ppap"] = m.captures[1])
    end
    
    parse_quality_audits!(data, doc)
    parse_performance_metrics!(data, doc)
    parse_certifications!(data, doc)
    
    println("   ✓ Supplier: $(data["name"]) ($(data["parmaId"]))")
    return data
end

function parse_quality_audits!(data::Dict, doc)
    metrics = data["metrics"]
    audit_panel = eachmatch(Selector("#IndexAuditPanel"), doc.root)
    isempty(audit_panel) && return
    
    audit_text = extract_text(first(audit_panel))
    
    #= SW Index =#
    sw_match = match(r"Software\s+Index(.+?)(?:EE Index|Polymer Index|$)"i, audit_text)
    if !isnothing(sw_match)
        sw_text = sw_match.captures[1]
        m = match(r"(\d+)%", sw_text)
        !isnothing(m) && (metrics["swIndex"] = m.captures[1] * "%")
        occursin("Approved", sw_text) && (metrics["swStatus"] = "Approved")
        occursin(r"Not [Aa]pproved", sw_text) && (metrics["swStatus"] = "Not Approved")
        m = match(r"(\d{4}-\d{2}-\d{2})", sw_text)
        if !isnothing(m)
            metrics["swDate"] = m.captures[1]
            try
                (today() - Date(m.captures[1])).value / 365.25 > 5.0 && (metrics["swStatus"] = "Expired")
            catch end
        end
    end
    
    #= EE Index =#
    ee_match = match(r"EE\s+Index(.+?)(?:Polymer Index|$)"i, audit_text)
    if !isnothing(ee_match)
        ee_text = ee_match.captures[1]
        m = match(r"(\d+)%", ee_text)
        !isnothing(m) && (metrics["eeIndex"] = m.captures[1] * "%")
        occursin("Approved with conditions", ee_text) && (metrics["eeStatus"] = "Approved with conditions")
        occursin("Approved", ee_text) && !haskey(metrics, "eeStatus") && (metrics["eeStatus"] = "Approved")
        m = match(r"(\d{4}-\d{2}-\d{2})", ee_text)
        !isnothing(m) && (metrics["eeDate"] = m.captures[1])
    end
    
    #= SMA =#
    sma_match = match(r"SMA\s*/\s*Criticality\s+1\s+Index(.+?)(?:Software Index|EE Index|$)"i, audit_text)
    if !isnothing(sma_match)
        sma_text = sma_match.captures[1]
        m = match(r"(\d+)%", sma_text)
        !isnothing(m) && (metrics["sma"] = m.captures[1] * "%")
        occursin("Approved", sma_text) && (metrics["smaStatus"] = "Approved")
        m = match(r"(\d{4}-\d{2}-\d{2})", sma_text)
        !isnothing(m) && (metrics["smaDate"] = m.captures[1])
    end
end

function parse_performance_metrics!(data::Dict, doc)
    table = eachmatch(Selector("#tblSales2"), doc.root)
    isempty(table) && return
    
    for row in eachmatch(Selector("tr"), first(table))
        cells = eachmatch(Selector("td"), row)
        length(cells) < 15 && continue
        
        brand_text = extract_text(cells[1])
        (isempty(brand_text) || occursin("Brand/Consignee", brand_text)) && continue
        
        if occursin("Supplier Total", brand_text)
            try
                data["ppm"]["lastPeriod"] = extract_text(cells[3])
                data["ppm"]["actual"] = extract_text(cells[4])
                ppm_l = tryparse(Float64, replace(data["ppm"]["lastPeriod"], r"[^0-9.-]" => ""))
                ppm_a = tryparse(Float64, replace(data["ppm"]["actual"], r"[^0-9.-]" => ""))
                if !isnothing(ppm_l) && !isnothing(ppm_a)
                    c = ppm_a - ppm_l
                    data["ppm"]["change"] = @sprintf("%+.1f", c)
                    data["ppm"]["trend"] = c > 0 ? "up" : c < 0 ? "down" : "neutral"
                end
                
                data["qpm"]["lastPeriod"] = extract_text(cells[7])
                data["qpm"]["actual"] = extract_text(cells[8])
                qpm_l = tryparse(Float64, replace(data["qpm"]["lastPeriod"], r"[^0-9.-]" => ""))
                qpm_a = tryparse(Float64, replace(data["qpm"]["actual"], r"[^0-9.-]" => ""))
                if !isnothing(qpm_l) && !isnothing(qpm_a)
                    c = qpm_a - qpm_l
                    data["qpm"]["change"] = @sprintf("%+.1f", c)
                    data["qpm"]["trend"] = c > 0 ? "up" : c < 0 ? "down" : "neutral"
                end
            catch end
            break
        end
    end
end

function parse_certifications!(data::Dict, doc)
    cert_table = eachmatch(Selector("#GridView1"), doc.root)
    isempty(cert_table) && return
    
    for row in eachmatch(Selector("tr"), first(cert_table))
        cells = eachmatch(Selector("td"), row)
        length(cells) < 4 && continue
        cert_name = extract_text(cells[1])
        (isempty(cert_name) || cert_name == "N/A") && continue
        push!(data["certifications"], Dict(
            "name" => cert_name,
            "certifiedPlace" => extract_text(cells[2]),
            "expiryDate" => extract_text(cells[3]),
            "status" => extract_text(cells[4])
        ))
    end
end

#= ═══════════════════════════════════════════════════════════════════════════════════
   DASHBOARD GENERATION
   ═══════════════════════════════════════════════════════════════════════════════════ =#

load_template(path::String) = isfile(path) ? read(path, String) : error("Template not found: $path")

function substitute_template(template::String, vars::Dict)::String
    result = template
    for (k, v) in vars
        result = replace(result, "{{$k}}" => string(v))
    end
    return result
end

function generate_dashboard(workspace::String, suppliers_data::Vector)
    println("\n" * "="^60)
    println("📊 GENERATING DASHBOARD")
    println("="^60)
    
    html_dir = joinpath(workspace, "dashboard")
    suppliers_dir = joinpath(html_dir, "suppliers")
    template_dir = joinpath(workspace, "temp")
    
    mkpath(suppliers_dir)
    
    index_template = joinpath(template_dir, "index.html")
    supplier_template = joinpath(template_dir, "supplier.html")
    
    if !isfile(index_template) || !isfile(supplier_template)
        println("❌ Templates not found - creating defaults")
        open(index_template, "w") do f write(f, get_default_index_template()) end
        open(supplier_template, "w") do f write(f, get_default_supplier_template()) end
    end
    
    generate_index_page(suppliers_data, html_dir, index_template)
    
    for supplier in suppliers_data
        generate_supplier_page(supplier, html_dir, supplier_template)
        #= Save JSON =#
        json_file = joinpath(suppliers_dir, "supplier_$(supplier["id"]).json")
        open(json_file, "w") do f write(f, JSON3.write(supplier)) end
    end
    
    index_path = joinpath(html_dir, "index.html")
    println("\n✅ Dashboard generated: $index_path")
    return index_path
end

function generate_index_page(suppliers::Vector, output_dir::String, template_file::String)
    template = load_template(template_file)
    
    cards_html = ""
    for s in suppliers
        parma = get(s, "parmaId", "N/A")
        name = get(s, "name", "Unknown")
        metrics = get(s, "metrics", Dict())
        qpm = get(s, "qpm", Dict())
        
        sw_status = get(metrics, "swStatus", "N/A")
        sw_class = sw_status == "Approved" ? "status-approved" : sw_status == "Expired" ? "status-expired" : "status-na"
        qpm_actual = get(qpm, "actual", "N/A")
        qpm_trend = get(qpm, "trend", "neutral")
        qpm_class = qpm_trend == "down" ? "trend-down" : qpm_trend == "up" ? "trend-up" : "trend-neutral"
        
        cards_html *= """<div class="supplier-card" onclick="window.location='supplier_$parma.html'"><h3>$name</h3><p class="parma">PARMA: $parma</p><div class="metrics-row"><span class="$sw_class">SW: $sw_status</span><span class="$qpm_class">QPM: $qpm_actual</span></div></div>"""
    end
    
    html = substitute_template(template, Dict(
        "SUPPLIER_CARDS" => cards_html,
        "TOTAL_SUPPLIERS" => length(suppliers),
        "GENERATED_DATE" => Dates.format(now(), "yyyy-mm-dd HH:MM:SS")
    ))
    
    open(joinpath(output_dir, "index.html"), "w") do f write(f, html) end
    println("   ✓ Generated: index.html")
end

function generate_supplier_page(supplier::Dict, output_dir::String, template_file::String)
    template = load_template(template_file)
    
    parma = get(supplier, "parmaId", "N/A")
    metrics = get(supplier, "metrics", Dict())
    qpm = get(supplier, "qpm", Dict())
    ppm = get(supplier, "ppm", Dict())
    
    sw_status = get(metrics, "swStatus", "N/A")
    sw_class = sw_status == "Approved" ? "status-approved" : sw_status == "Expired" ? "status-expired" : "status-na"
    ee_status = get(metrics, "eeStatus", "N/A")
    ee_class = ee_status == "Approved" ? "status-approved" : "status-na"
    qpm_class = get(qpm, "trend", "neutral") == "down" ? "trend-down" : get(qpm, "trend", "neutral") == "up" ? "trend-up" : "trend-neutral"
    ppm_class = get(ppm, "trend", "neutral") == "down" ? "trend-down" : get(ppm, "trend", "neutral") == "up" ? "trend-up" : "trend-neutral"
    
    certs_html = join(["<tr><td>$(get(c,"name","N/A"))</td><td>$(get(c,"certifiedPlace","N/A"))</td><td>$(get(c,"expiryDate","N/A"))</td><td>$(get(c,"status","N/A"))</td></tr>" for c in get(supplier, "certifications", [])])
    
    html = substitute_template(template, Dict(
        "SUPPLIER_NAME" => get(supplier, "name", "Unknown"),
        "SUPPLIER_ID" => get(supplier, "id", "N/A"),
        "PARMA_ID" => parma,
        "SUPPLIER_LOGO" => get(supplier, "logo", ""),
        "APQP" => get(supplier, "apqp", "N/A"),
        "PPAP" => get(supplier, "ppap", "N/A"),
        "SW_INDEX" => get(metrics, "swIndex", "N/A"),
        "SW_STATUS" => sw_status, "SW_DATE" => get(metrics, "swDate", "N/A"), "SW_CLASS" => sw_class,
        "EE_INDEX" => get(metrics, "eeIndex", "N/A"),
        "EE_STATUS" => ee_status, "EE_DATE" => get(metrics, "eeDate", "N/A"), "EE_CLASS" => ee_class,
        "SMA" => get(metrics, "sma", "N/A"),
        "SMA_STATUS" => get(metrics, "smaStatus", "N/A"), "SMA_DATE" => get(metrics, "smaDate", "N/A"),
        "QPM_LAST" => get(qpm, "lastPeriod", "N/A"),
        "QPM_ACTUAL" => get(qpm, "actual", "N/A"), "QPM_CHANGE" => get(qpm, "change", "N/A"), "QPM_CLASS" => qpm_class,
        "PPM_LAST" => get(ppm, "lastPeriod", "N/A"),
        "PPM_ACTUAL" => get(ppm, "actual", "N/A"), "PPM_CHANGE" => get(ppm, "change", "N/A"), "PPM_CLASS" => ppm_class,
        "CERTIFICATIONS_HTML" => certs_html,
        "GENERATED_DATE" => Dates.format(now(), "yyyy-mm-dd HH:MM:SS")
    ))
    
    open(joinpath(output_dir, "supplier_$parma.html"), "w") do f write(f, html) end
    println("   ✓ Generated: supplier_$parma.html")
end

#= ═══════════════════════════════════════════════════════════════════════════════════
   NOTIFICATION GENERATION
   ═══════════════════════════════════════════════════════════════════════════════════ =#

function generate_notifications(suppliers_data::Vector, myemail::String)
    notifications = []
    
    for supplier in suppliers_data
        parma = get(supplier, "parmaId", "UNKNOWN")
        name = get(supplier, "name", "Unknown")
        metrics = get(supplier, "metrics", Dict())
        qpm = get(supplier, "qpm", Dict())
        
        #= QPM alerts =#
        qpm_actual = tryparse(Float64, replace(get(qpm, "actual", "N/A"), r"[^0-9.-]" => ""))
        qpm_last = tryparse(Float64, replace(get(qpm, "lastPeriod", "N/A"), r"[^0-9.-]" => ""))
        
        if !isnothing(qpm_actual) && !isnothing(qpm_last)
            if qpm_actual >= qpm_last * 1.1 && qpm_last > 0
                push!(notifications, create_qpm_alert(parma, name, qpm_last, qpm_actual, myemail, "increase_10"))
            end
            if qpm_actual >= 30 && qpm_actual <= 50
                push!(notifications, create_qpm_alert(parma, name, qpm_last, qpm_actual, myemail, "warning_30_50"))
            elseif qpm_actual > 50
                push!(notifications, create_qpm_alert(parma, name, qpm_last, qpm_actual, myemail, "critical_over_50"))
            end
        end
        
        #= SW Index expiration =#
        get(metrics, "swStatus", "N/A") == "Expired" && push!(notifications, create_sw_index_alert(parma, name, get(metrics, "swDate", ""), myemail))
        
        #= Certification expiry =#
        for cert in get(supplier, "certifications", [])
            check_certification_expiry!(notifications, parma, name, cert, myemail)
        end
    end
    
    return notifications
end

function create_qpm_alert(parma, name, qpm_last, qpm_actual, email, alert_type)
    change = qpm_actual - qpm_last
    change_pct = qpm_last > 0 ? (change / qpm_last) * 100 : 0
    
    subject, priority, color = if alert_type == "increase_10"
        ("QPM Alert: 10% Increase for PARMA $parma", 3, "#0066cc")
    elseif alert_type == "warning_30_50"
        ("QPM Warning: Approaching 50 for PARMA $parma", 2, "#ff9900")
    else
        ("🚨 CRITICAL: QPM Over 50 for PARMA $parma", 1, "#cc0000")
    end
    
    body = """<html><body style="font-family: Arial, sans-serif;"><h2 style="color: $color;">QPM Alert - $name</h2><p>Supplier <a href="https://vsib.srv.volvo.com/vsib/Content/sus/SupplierScorecard.aspx?SupplierId=$parma"><strong>PARMA $parma</strong></a></p><table style="border-collapse: collapse; margin: 20px 0;"><tr><td style="padding: 8px; border: 1px solid #ddd;"><strong>Last Period QPM:</strong></td><td style="padding: 8px; border: 1px solid #ddd;">$qpm_last</td></tr><tr><td style="padding: 8px; border: 1px solid #ddd;"><strong>Actual QPM:</strong></td><td style="padding: 8px; border: 1px solid #ddd;">$qpm_actual</td></tr><tr><td style="padding: 8px; border: 1px solid #ddd;"><strong>Change:</strong></td><td style="padding: 8px; border: 1px solid #ddd;">$(@sprintf("%+.1f", change)) ($(@sprintf("%+.1f%%", change_pct)))</td></tr></table><p>Best regards,<br>QPrism</p></body></html>"""
    
    return Dict("recipient" => email, "subject" => subject, "body" => body, "priority" => priority, "type" => "qpm_$alert_type", "parma" => parma)
end

function create_sw_index_alert(parma, name, sw_date, email)
    body = """<html><body style="font-family: Arial, sans-serif;"><h2 style="color: #cc0000;">SW Index Expired - $name</h2><p>Supplier <a href="https://vsib.srv.volvo.com/vsib/Content/sus/SupplierScorecard.aspx?SupplierId=$parma"><strong>PARMA $parma</strong></a></p><p>The Software Index audit has <strong style="color: #cc0000;">EXPIRED</strong> (last audit: $sw_date).</p><p><strong>Action Required:</strong> Schedule new SW Index audit.</p><p>Best regards,<br>QPrism</p></body></html>"""
    return Dict("recipient" => email, "subject" => "🚨 SW Index EXPIRED: PARMA $parma", "body" => body, "priority" => 1, "type" => "sw_index_expired", "parma" => parma)
end

function check_certification_expiry!(notifications, parma, name, cert, email)
    expiry_str = get(cert, "expiryDate", "")
    cert_name = get(cert, "name", "Unknown")
    isempty(expiry_str) && return
    
    try
        expiry_date = Date(expiry_str, dateformat"yyyy-mm-dd")
        days_until = (expiry_date - today()).value
        
        subject, priority, color, message = if days_until <= 0
            ("🚨 Certification EXPIRED: $cert_name (PARMA $parma)", 1, "#cc0000", "has <strong style='color: #cc0000;'>EXPIRED</strong> ($(abs(days_until)) days ago)")
        elseif days_until <= 90
            ("Certification Expiring Soon: $cert_name (PARMA $parma)", 2, "#ff9900", "expires in <strong style='color: #ff9900;'>$days_until days</strong>")
        elseif days_until <= 180
            ("Certification Notice: $cert_name (PARMA $parma)", 3, "#0066cc", "expires in <strong>$days_until days</strong>")
        else
            return
        end
        
        body = """<html><body style="font-family: Arial, sans-serif;"><h2 style="color: $color;">Certification Alert - $name</h2><p>Supplier <a href="https://vsib.srv.volvo.com/vsib/Content/sus/SupplierScorecard.aspx?SupplierId=$parma"><strong>PARMA $parma</strong></a></p><p>Certification <strong>$cert_name</strong> $message</p><table style="border-collapse: collapse; margin: 20px 0;"><tr><td style="padding: 8px; border: 1px solid #ddd;"><strong>Certification:</strong></td><td style="padding: 8px; border: 1px solid #ddd;">$cert_name</td></tr><tr><td style="padding: 8px; border: 1px solid #ddd;"><strong>Expiry Date:</strong></td><td style="padding: 8px; border: 1px solid #ddd;">$expiry_str</td></tr></table><p>Best regards,<br>QPrism</p></body></html>"""
        
        push!(notifications, Dict("recipient" => email, "subject" => subject, "body" => body, "priority" => priority, "type" => "cert_expiry", "parma" => parma))
    catch end
end

#= ═══════════════════════════════════════════════════════════════════════════════════
   EMAIL SENDING (using Sendmail.jl)
   ═══════════════════════════════════════════════════════════════════════════════════ =#

function send_notifications(workspace::String, notifications::Vector)
    println("\n" * "="^60)
    println("📧 SENDING EMAIL NOTIFICATIONS")
    println("="^60)
    
    isempty(notifications) && (println("ℹ️  No notifications to send"); return 0)
    
    config_path = joinpath(workspace, "conf", "config.toml")
    
    if isfile(config_path)
        try
            Sendmail.configure(config_path)
            println("✓ SMTP configured")
        catch e
            println("⚠️  SMTP config error: $e")
            return 0
        end
    else
        println("❌ config.toml not found - cannot send emails")
        return 0
    end
    
    sent = 0
    for (i, notif) in enumerate(notifications)
        println("\n[$i/$(length(notifications))] $(notif["type"])")
        println("   To: $(notif["recipient"])")
        println("   Subject: $(notif["subject"])")
        
        try
            Sendmail.send(notif["recipient"], notif["subject"], notif["body"]; ishtml=true)
            println("   ✅ Sent")
            sent += 1
        catch e
            println("   ❌ Failed: $e")
        end
        sleep(0.5)
    end
    
    println("\n📊 Sent: $sent/$(length(notifications)) emails")
    return sent
end

#= ═══════════════════════════════════════════════════════════════════════════════════
   DASHBOARD VIEWER
   ═══════════════════════════════════════════════════════════════════════════════════ =#

function open_dashboard(workspace::String)
    dashboard_path = joinpath(workspace, "dashboard", "index.html")
    
    if !isfile(dashboard_path)
        println("❌ Dashboard not found. Generate it first (option 1)")
        return
    end
    
    abs_path = abspath(dashboard_path)
    file_url = Sys.iswindows() ? "file:///" * replace(abs_path, "\\" => "/") : "file://" * abs_path
    
    println("\n🌐 Opening dashboard: $file_url")
    
    if !launch_chromedriver()
        #= Fallback to default browser =#
        if Sys.iswindows()
            run(`cmd /c start "" "$abs_path"`, wait=false)
        elseif Sys.isapple()
            run(`open "$abs_path"`, wait=false)
        else
            run(`xdg-open "$abs_path"`, wait=false)
        end
        return
    end
    
    local session = nothing
    try
        capabilities = Capabilities("chrome")
        wd = RemoteWebDriver(capabilities, host="localhost", port=DEFAULT_WEBDRIVER_PORT)
        session = Session(wd)
        navigate!(session, file_url)
        
        println("\n✅ Dashboard opened!")
        println("   Press Enter to close...")
        readline()
    catch e
        println("⚠️  Error: $e")
        Sys.iswindows() && run(`cmd /c start "" "$abs_path"`, wait=false)
    finally
        !isnothing(session) && try delete!(session) catch end
        terminate_chromedriver()
    end
end

#= ═══════════════════════════════════════════════════════════════════════════════════
   MAIN WORKFLOW FUNCTIONS
   ═══════════════════════════════════════════════════════════════════════════════════ =#

function run_dashboard_workflow(workspace::String)
    println("\n" * "="^70)
    println("🚀 QPRISM DASHBOARD GENERATION")
    println("="^70)
    
    parma_codes, myemail = load_suppliers_config(workspace)
    
    if isnothing(parma_codes) || isempty(parma_codes)
        println("\n❌ No PARMA codes configured.")
        println("   Edit: $(joinpath(workspace, "conf", "suppliers.toml"))")
        return
    end
    
    println("\n📡 Step 1/3: Scraping supplier data...")
    scrape_all_suppliers(workspace, parma_codes)
    
    println("\n📄 Step 2/3: Parsing supplier data...")
    data_dir = joinpath(workspace, "data")
    html_files = filter(f -> endswith(f, ".html"), readdir(data_dir))
    
    suppliers_data = []
    for html_file in html_files
        try
            push!(suppliers_data, parse_supplier_html(joinpath(data_dir, html_file)))
        catch e
            println("   ❌ Error: $html_file - $e")
        end
    end
    
    isempty(suppliers_data) && (println("\n❌ No supplier data parsed"); return)
    
    println("\n📊 Step 3/3: Generating dashboard...")
    dashboard_path = generate_dashboard(workspace, suppliers_data)
    
    if !isnothing(dashboard_path)
        println("\n✅ Dashboard ready!")
        print("   Open in browser? (y/n): ")
        answer = lowercase(strip(readline()))
        (answer == "y" || answer == "yes") && open_dashboard(workspace)
    end
end

function run_email_workflow(workspace::String)
    println("\n" * "="^70)
    println("📧 QPRISM EMAIL NOTIFICATIONS")
    println("="^70)
    
    parma_codes, myemail = load_suppliers_config(workspace)
    
    if isempty(myemail)
        println("\n❌ No email configured.")
        println("   Edit: $(joinpath(workspace, "conf", "suppliers.toml"))")
        return
    end
    
    data_dir = joinpath(workspace, "data")
    html_files = filter(f -> endswith(f, ".html"), readdir(data_dir, join=false))
    
    if isempty(html_files)
        if isnothing(parma_codes) || isempty(parma_codes)
            println("\n❌ No PARMA codes and no existing data.")
            println("   Edit: $(joinpath(workspace, "conf", "suppliers.toml"))")
            return
        end
        println("📡 No cached data - scraping suppliers...")
        scrape_all_suppliers(workspace, parma_codes)
        html_files = filter(f -> endswith(f, ".html"), readdir(data_dir, join=false))
    end
    
    suppliers_data = []
    for html_file in html_files
        try
            push!(suppliers_data, parse_supplier_html(joinpath(data_dir, html_file)))
        catch e
            println("   ❌ Error: $html_file - $e")
        end
    end
    
    isempty(suppliers_data) && (println("\n❌ No supplier data available"); return)
    
    println("\n📋 Analyzing supplier data...")
    notifications = generate_notifications(suppliers_data, myemail)
    
    if isempty(notifications)
        println("\n✅ All suppliers within normal parameters - no alerts needed")
        return
    end
    
    println("\n📬 Found $(length(notifications)) notifications:")
    for (i, n) in enumerate(notifications)
        emoji = n["priority"] == 1 ? "🔴" : n["priority"] == 2 ? "🟡" : "🔵"
        println("   $emoji [$i] $(n["subject"])")
    end
    
    print("\nSend notifications? (y/n): ")
    answer = lowercase(strip(readline()))
    (answer == "y" || answer == "yes") ? send_notifications(workspace, notifications) : println("ℹ️  Notifications not sent")
end

#= ═══════════════════════════════════════════════════════════════════════════════════
   MAIN ENTRY POINT
   ═══════════════════════════════════════════════════════════════════════════════════ =#

#= qprismrun()
   Main entry point for QPrism. Run this after `using Qprism`. =#
function qprismrun()
    println()
    println("╔══════════════════════════════════════════════════════════════════════╗")
    println("║                                                                      ║")
    println("║   ██████╗ ██████╗ ██████╗ ██╗███████╗███╗   ███╗                     ║")
    println("║  ██╔═══██╗██╔══██╗██╔══██╗██║██╔════╝████╗ ████║                     ║")
    println("║  ██║   ██║██████╔╝██████╔╝██║███████╗██╔████╔██║                     ║")
    println("║  ██║▄▄ ██║██╔═══╝ ██╔══██╗██║╚════██║██║╚██╔╝██║                     ║")
    println("║  ╚██████╔╝██║     ██║  ██║██║███████║██║ ╚═╝ ██║                     ║")
    println("║   ╚══▀▀═╝ ╚═╝     ╚═╝  ╚═╝╚═╝╚══════╝╚═╝     ╚═╝                     ║")
    println("║                                                                      ║")
    println("║         Volvo Supplier Quality Notification System                   ║")
    println("║                                                                      ║")
    println("╚══════════════════════════════════════════════════════════════════════╝")
    println()
    
    workspace = init_workspace()
    
    while true
        println("\n" * "─"^50)
        println("  What would you like to do?")
        println("─"^50)
        println("  [1] 📊 Generate Dashboard")
        println("  [2] 📧 Send Email Notifications")
        println("  [3] 🚪 Quit")
        println("─"^50)
        print("  Enter choice (1-3): ")
        
        choice = strip(readline())
        
        if choice == "1"
            run_dashboard_workflow(workspace)
        elseif choice == "2"
            run_email_workflow(workspace)
        elseif choice == "3"
            println("\n👋 Goodbye!")
            break
        else
            println("\n⚠️  Invalid choice. Please enter 1, 2, or 3.")
        end
    end
end

end #= module =#
