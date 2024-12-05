
#!/usr/bin/env pwsh
#region    Classes

class JsonCli {
  static hidden [hashtable] $parsers

  static JsonCli() {
    [JsonCli]::parsers = [JsonCli]::GetParsers()
  }

  static [string] GetParser([string]$Command) {
    # Extract the base command (everything before the first space)
    $BaseCommand = $Command.Split(' ')[0]

    if ([JsonCli]::parsers.ContainsKey($BaseCommand)) {
      return [JsonCli]::parsers[$BaseCommand]
    }

    # Regex-based fallback for similar commands
    $p = switch -regex ($BaseCommand) {
      "*json*" { "--json"; break }
      "*xml*" { "--xml"; break }
      "*csv*" { "--csv"; break }
      "*log*" { "--syslog"; break }
      "*config*" { "--ssh-conf"; break }
      default {
        Write-Warning "No predefined parser found for '$Command'."
        $null
      }
    }
    return $p
  }
  static [string] ParseGeneric([string[]]$Lines) {
    $ParsedOutput = foreach ($Line in $Lines) {
      [PSCustomObject]@{ RawLine = $Line }
    }
    return $ParsedOutput | ConvertTo-Json -Depth 1
  }
  static [string] RunCommand([string]$Command) {
    $Parser = [JsonCli]::GetParser($Command) -or [JsonCli]::GetFallbackParser($Command)
    # if ($null -eq $Parser) {
    #   throw [System.Exception]::new("No parser available for the command: $Command")
    # }

    if ($null -eq $Parser) {
      Write-Warning "No parser available for the command: $Command. Falling back to generic parsing."
      return [JsonCli]::ParseGeneric([JsonCli]::ExecuteCommand($Command))
    }

    try {
      $Output = [scriptblock]::create("$Command").Invoke() | jc $Parser
      return $Output
    } catch {
      Write-Warning "Parser execution failed: $Command"
      return [JsonCli]::ParseGeneric([JsonCli]::ExecuteCommand($Command))
    }
  }
  static [string[]] ExecuteCommand([string]$Command) {
    try {
      return [scriptblock]::create("$Command").Invoke()
    } catch {
      Write-Warning "Failed to execute command: $Command"
      return @()
    }
  }
  static [string] RunFallback([string]$Command) {
    $Output = & $Command
    $Lines = $Output -split "`n"
    return [JsonCli]::ParseGeneric($Lines)
  }
  static [hashtable] GetParsers() {
    $p = @{}
    try {
      # Run 'jc -hhh' to get categorized parsers
      $Output = jc -hhh
      $Lines = $Output -split "`n"

      foreach ($Line in $Lines) {
        # Match parser lines like '--csv                 CSV file parser'
        if ($Line -match '^(?<Parser>\-\-\S+)\s+(?<Description>.+)$') {
          # Extract the base command (e.g., 'csv' from '--csv')
          $Command = ($Matches['Parser'] -replace '^\-\-', '').Split('-')[0]
          $p[$Command] = $Matches['Parser']
        }
      }

      if ($p.Count -eq 0) {
        Write-Warning "No parsers found. Check if 'jc' is installed and accessible."
      }
    } catch {
      Write-Warning "Failed to fetch parsers from 'jc'. Ensure it's installed and working."
    }
    return $p
  }
  static [void] Log([string]$Message, [string]$LogLevel = "Info") {
    $Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Write-Host "[$LogLevel] ${Timestamp}: $Message"
  }
}
#endregion Classes
# Types that will be available to users when they import the module.
$typestoExport = @(
  [JsonCli]
)
$TypeAcceleratorsClass = [PsObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
foreach ($Type in $typestoExport) {
  if ($Type.FullName -in $TypeAcceleratorsClass::Get.Keys) {
    $Message = @(
      "Unable to register type accelerator '$($Type.FullName)'"
      'Accelerator already exists.'
    ) -join ' - '

    [System.Management.Automation.ErrorRecord]::new(
      [System.InvalidOperationException]::new($Message),
      'TypeAcceleratorAlreadyExists',
      [System.Management.Automation.ErrorCategory]::InvalidOperation,
      $Type.FullName
    ) | Write-Warning
  }
}
# Add type accelerators for every exportable type.
foreach ($Type in $typestoExport) {
  $TypeAcceleratorsClass::Add($Type.FullName, $Type)
}
# Remove type accelerators when the module is removed.
$MyInvocation.MyCommand.ScriptBlock.Module.OnRemove = {
  foreach ($Type in $typestoExport) {
    $TypeAcceleratorsClass::Remove($Type.FullName)
  }
}.GetNewClosure();

$scripts = @();
$Public = Get-ChildItem "$PSScriptRoot/Public" -Filter "*.ps1" -Recurse -ErrorAction SilentlyContinue
$scripts += Get-ChildItem "$PSScriptRoot/Private" -Filter "*.ps1" -Recurse -ErrorAction SilentlyContinue
$scripts += $Public

foreach ($file in $scripts) {
  Try {
    if ([string]::IsNullOrWhiteSpace($file.fullname)) { continue }
    . "$($file.fullname)"
  } Catch {
    Write-Warning "Failed to import function $($file.BaseName): $_"
    $host.UI.WriteErrorLine($_)
  }
}

$Param = @{
  Function = $Public.BaseName
  Cmdlet   = '*'
  Alias    = '*'
}
Export-ModuleMember @Param
