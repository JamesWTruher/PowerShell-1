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
    param ( $tType )
    if ( $IsLinux ) {
        $platform = "Linux"
        $eTag = "RequireSudoOnUnix"
    }
    elseif ( $IsMacOS ) {
        $platform = "MacOS"
        $eTag = "RequireSudoOnUnix"
    }
    else {
        $platform = "Windows"
        $eTag = "RequireAdminOnWindows"
    }

    Import-Module ./build.psm1
    Restore-PSOptions
    # set up environment for running coverage
    if ( $IsWindows ) {
        find-dotnet
        $dotnetRoot = "$HOME/AppData/Local/Microsoft/dotnet"
    }
    else {
        $dotnetRoot = "$HOME/.dotnet"
    }
    $dotnetToolRoot = "$HOME/.dotnet/tools"
    $env:PATH += [io.path]::PathSeparator + $dotnetRoot
    $env:PATH += [io.path]::PathSeparator + $dotnetToolRoot
    $env:DOTNET_ROOT = $dotnetRoot
    # last check before starting coverage run
    Get-Command dotnet
    $null = Get-Command dotnet -ErrorAction Stop
    Get-Command coverlet
    $null = Get-Command coverlet -ErrorAction Stop
    # set up arguments for calling
    $psexePath = (Get-PSOptions).Output
    $psexeDir = [System.IO.Path]::GetDirectoryName($psexePath)
    $cArgs = @()
    $cArgs += '--target'
    $cArgs += $psexePath
    $cArgs += '--targetargs'
    if ( $tType -eq "elevated" ) {
        if ( $IsWindows ) {
            $script = "import-module ./build.psm1;Start-PSPester -exclu @() -Tag ${eTag}"
        }
        else {
            $script = "import-module ./build.psm1;`$r=Start-PSPester -Sudo -Pass -exclu @() -Tag ${eTag};`$t=[io.path]::GetTempPath();sudo chown (id -u) `$t/Mic* `$t/System* `$t/pwsh*"
        }
    }
    else {
        if ( $IsWindows ) {
            $script = 'import-module ./build.psm1;Start-PSPester -exclu @("RequireSudoOnUnix","RequireSudoOnUnix") -Tag CI,Feature,Slow'
        }
        else {
            $script = 'import-module ./build.psm1;Start-PSPester -exclu @("RequireSudoOnUnix","RequireSudoOnUnix") -Tag CI,Feature,Slow'
        }
    }
    $outputFilename = "${platform}-${tType}-coverage"
    #; $result +=start-pspester -pass -sudo -Tag RequireSudoOnUnix -Exclude @()'
    $encodedCommand =  [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script))
    $cArgs += "-nopr -encodedcommand $encodedCommand"
    $cArgs += '--include=[Microsoft.PowerShell.Commands.Management]*,[Microsoft.PowerShell.Commands.Utility]*,[Microsoft.PowerShell.ConsoleHost]*,[Microsoft.PowerShell.MarkdownRender]*,[Microsoft.PowerShell.SDK]*,[Microsoft.PowerShell.Security]*,[System.Management.Automation]*,[pwsh]*'
    $cArgs += '--verbosity'
    $cArgs += 'detailed'
    $cArgs += '--format'
    $cArgs += 'opencover'
    $cArgs += '--output'
    $cArgs += "$outputFilename"
    $cARgs += '--include-test-assembly'
    $cArgs += $psexeDir
    coverlet $cArgs
    # see if we have an xml file!
    Get-ChildItem *.xml
    $opencoverFile = Get-ChildItem "${outputFileName}.opencover.xml"
    $opencoverFullName = $opencoverFile.FullName
    Write-Host "##vso[artifact.upload containerfolder=artifact;artifactname=artifact]$opencoverFullName"
    exit 0
}
