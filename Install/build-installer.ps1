
#-------------------------------------------------------------------------------
# parameters
#-------------------------------------------------------------------------------

Param(  [switch]$sign = $false,
	      [switch]$build = $false,
        [switch]$installer = $false,
        [switch]$console = $false,
        [switch]$x86 = $false,
        [switch]$x64 = $false,
        [switch]$clean = $false,
        [switch]$zip = $false,
        [switch]$all = $false,
        [string]$logfile = "build-log.txt" );

if( $all ) {
  $console = $TRUE;
  $sign = $TRUE;
  $build = $TRUE;
  $installer = $TRUE;
  $x64 = $TRUE;
  $x86 = $TRUE;
  $zip = $TRUE;
};

$logfile = Resolve-Path $logfile

#-------------------------------------------------------------------------------
# functions
#-------------------------------------------------------------------------------

#
# read the version string from the header file
#
Function GetVersion() {
	$m = select-string ..\BERT\BERT\include\BERT_Version.h -pattern "BERT_VERSION\s+L""(.*)"""
	$v  = $m.Matches[0].Groups[1].Value
	return $v;
}

#
# exit on error, with message
#
Function ExitOnError( $message ) {

	if( $LastExitCode -ne 0 ){
		if( $message -ne $null ){ Write-Host "$message" -foregroundcolor red ; }
		Write-Host "  Exit on error: $LastExitCode`r`n" -foregroundcolor red ;
		Exit $LastExitCode;
	}
	else {
		# Write-Host "LE? $LastExitCode";
	}
}

#
# build one config 
#
Function BuildConfiguration( $platform ) {
	$extraargs = "";
	if( $clean ){
		$extraargs = "/t:Clean,Build"
		Write-Host "  Configuration: $platform (clean+build)" -foregroundcolor yellow
	}
	else {
		Write-Host "  Configuration: $platform (build)" -foregroundcolor yellow
	}
	msbuild '..\BERT\BERT.sln' /p:Configuration=Release /p:platform=$platform /m $extraargs | out-file -append -encoding "utf8" $logfile 2>&1
	ExitOnError ;
}

#
# setup environment. thanks to
# https://github.com/nightroman/PowerShelf/blob/master/Invoke-Environment.ps1
#
Function InvokeEnvironment(){
  
  param
  (
    [Parameter(Mandatory=1)][string]$Directory,
    [Parameter(Mandatory=1)][string]$Command,
    [switch]$Output,
    [switch]$Force
  )

  $stream = if ($Output) { ($temp = [IO.Path]::GetTempFileName()) } else { 'nul' }
  $operator = if ($Force) {'&'} else {'&&'}

  Write-Host "Dir: $Directory";
  Write-Host "Cmd: $Command";

  Push-Location $Directory;
  foreach($_ in cmd /c " $Command > `"$stream`" 2>&1 $operator SET") {
    if ($_ -match '^([^=]+)=(.*)') {
      [System.Environment]::SetEnvironmentVariable($matches[1], $matches[2])
    }
  }
  Pop-Location;

  if ($Output) {
    Get-Content -LiteralPath $temp
    Remove-Item -LiteralPath $temp
  }

}

function ZipFile( $zipfile, $file )
{
  Add-Type -Assembly System.IO.Compression

  $current = Get-Location
  $resolved = Join-Path $current $file
  $zipfile = Join-Path $current $zipfile

  # use update in case there's an existing file (we run more than once)
  $archive = [System.IO.Compression.ZipFile]::Open($zipfile, [System.IO.Compression.ZipArchiveMode]::Update)

  # if you do that, then you have to check for an entry and delete it
  $entry = $archive.GetEntry($file)
  if($entry) { $entry.Delete() }

  $entry = $archive.CreateEntry($file)
  $output_stream = $entry.Open()
  [System.IO.File]::OpenRead($resolved).CopyTo($output_stream)
  $output_stream.Flush()
  $output_stream.Close()
  $archive.Dispose()
}

#-------------------------------------------------------------------------------
# runtime
#-------------------------------------------------------------------------------

InvokeEnvironment "C:\Program Files (x86)\Microsoft Visual Studio\2017\Enterprise\" "Common7\Tools\VsDevCmd.bat";

$bert_version = GetVersion;

Write-Host ""
Write-Host "Building installer for BERT Version $bert_version" -ForegroundColor blue

#
# reset log file
#

$startdate = Get-Date ;
Set-Content $logfile "Starting build @ $startdate`r`n" ;

Write-Host "Build started @ $startdate" -ForegroundColor blue
Write-Host ""

#
# console
#

if($console){
  Write-Host "Building console..." -ForegroundColor green
  Push-Location ..\Console
  & yarn run repackage | out-file -append -encoding "utf8"  $logfile 2>&1
  Pop-Location
  ExitOnError
}
else {
	Write-Host "Skipping build" -foregroundcolor gray
}

Write-Host ""

#
# build -- this is composite
#

if($build){
	Write-Host "Building configurations..." -ForegroundColor green
	if( $x86 -or $x64 ){
    if( $x86 ){ 
      BuildConfiguration "x86" 
		  ExitOnError
    }
		if( $x64 ){ 
      BuildConfiguration "x64" 
      ExitOnError
    }
	}
	else {
    Write-Host "  No configurations selected (use -x86 and/or -x64)" -foregroundcolor red
    Write-Host ""
    Exit 1;
	}
}
else {
	Write-Host "Skipping build" -foregroundcolor gray
}

Write-Host ""

#
# installer
#

if($installer){
	Write-Host "Building installer" -ForegroundColor green
  & 'C:\Program Files (x86)\NSIS\makensis.exe' /DVERSION=$bert_version install-script.nsi
  ExitOnError

  # nsis holds a lock on the output file, which breaks the next command.
  # not sure what this is about, but 1s is not sufficient. 
  Start-Sleep 3
}
else {
	Write-Host "Skipping installer" -foregroundcolor gray
}

Write-Host ""

#
# sign installer
#

if( $sign ) {
	Write-Host "Signing installer" -ForegroundColor green
	& cmd /c 'signtool.exe' sign /t http://timestamp.comodoca.com/authenticode /a /i comodo BERT-Installer-$bert_version.exe | out-file -append -encoding "utf8"  $logfile 2>&1
	ExitOnError ;
}
else {
	Write-Host "Not signing installer" -foregroundcolor gray;
}

Write-Host ""

#
# zip installer
#

if( $zip ) {
	Write-Host "Creating zip file" -ForegroundColor green
  ZipFile "BERT-Installer-$bert_version.zip" "BERT-Installer-$bert_version.exe"
  ExitOnError;
}
else {
	Write-Host "Not creating zip file" -foregroundcolor gray;
}

Write-Host ""

#-------------------------------------------------------------------------------
# done
#-------------------------------------------------------------------------------

$enddate = Get-Date ;
$elapsed = $enddate - $startdate;

Add-Content $logfile "Build complete @ $enddate`r`n" ;

Write-Host "Build finished @ $enddate" -ForegroundColor blue
Write-Host "Elapsed time $elapsed" -ForegroundColor blue
Write-Host ""



