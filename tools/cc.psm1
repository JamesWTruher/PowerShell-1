# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

# install the tools that we need to enable collecting coverage
function Start-CoverageBootstrap
{
    Import-Module ./build.psm1
    Start-PSBootStrap
    [string]$tools = dotnet tool list --global
    if ( $tools -notmatch "coverlet\,console" ) {
        Write-Verbose -Verbose "Installing Coverlet"
        dotnet tool install coverlet.console --global
    }
}

# create the build
function Start-CoverageBuild
{
    Import-Module ./build.psm1
    Start-PSBuild -PSModuleRestore -Configuration Debug
    Save-PSOptions
}

function Start-CoverageRun
{
    param ( $platform )
    Import-Module ./build.psm1
    Restore-PSOptions
    # set up environment for running coverage
    if ( $IsWindows ) {
        $dotnetRoot = "$HOME/AppData/Local/Microsoft/dotnet"
    }
    else {
        $dotnetRoot = "$HOME/.dotnet"
    }
    $env:PATH += [io.path]::PathSeparator + $dotnetRoot
    $env:PATH += [io.path]::PathSeparator + $dotnetRoot + "/tools"
    $env:DOTNET_ROOT = $dotnetRoot
    # last check before starting coverage run
    $null = Get-Command dotnet -ErrorAction Stop
    $null = Get-Command coverlet -ErrorAction Stop
    # set up arguments for calling
    $psexePath = (Get-PSOptions).Output
    $psexeDir = [System.IO.Path]::GetDirectoryName($psexePath)
    $cArgs = @()
    $cArgs += '--target'
    $cArgs += $psexePath
    $cArgs += '--targetargs'
    $script = 'import-module ./build.psm1;Start-PSPester -exclu @("RequireSudoOnUnix") -Tag CI,Feature,Slow'
    #; $result +=start-pspester -pas-sudo -Tag RequireSudoOnUnix -Exclude @()'
    $encodedCommand =  [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script))
    $cArgs += "-nopr -encodedcommand $encodedCommand"
    $cArgs += '--include=[Microsoft.PowerShell.Commands.Management]*,[Microsoft.PowerShell.Commands.Utility]*,[Microsoft.PowerShell.ConsoleHost]*,[Microsoft.PowerShell.MarkdownRender]*,[Microsoft.PowerShell.SDK]*,[Microsoft.PowerShell.Security]*,[System.Management.Automation]*,[pwsh]*'
    $cArgs += '--verbosity'
    $cArgs += 'detailed'
    $cArgs += '--format'
    $cArgs += 'opencover'
    $cArgs += '--output'
    $cArgs += "${platform}-coverage"
    $cARgs += '--include-test-assembly'
    $cArgs += $psexeDir
    coverlet $cArgs
    # see if we have an xml file!
    Get-ChildItem *.xml
}
