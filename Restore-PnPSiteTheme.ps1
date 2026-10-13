[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param (
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Path,

    [Parameter()]
    [switch]$IgnoreSiteUrlMismatch
)

#
# Validate the export file.
#

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Theme export file was not found: $Path"
}

try {
    $themeConfiguration = Get-Content -LiteralPath $Path -Raw |
    ConvertFrom-Json
}
catch {
    throw "The file is not valid JSON. $($_.Exception.Message)"
}

if (-not $themeConfiguration.ExportVersion) {
    throw "The JSON file does not contain an ExportVersion property."
}

if ([int]$themeConfiguration.ExportVersion -ne 1) {
    throw (
        "Unsupported theme export version: {0}. This function supports version 1." -f
        $themeConfiguration.ExportVersion
    )
}

if (-not $themeConfiguration.Site) {
    throw "The JSON file does not contain site information."
}

if ([string]::IsNullOrWhiteSpace([string]$themeConfiguration.Site.Url)) {
    throw "The JSON file does not contain the original site URL."
}

if (-not $themeConfiguration.Theme) {
    throw "The JSON file does not contain theme information."
}

if ([string]::IsNullOrWhiteSpace([string]$themeConfiguration.Theme.Name)) {
    throw (
        "The exported theme has no detected name. " +
        "The theme cannot be restored safely by name."
    )
}

if ([string]::IsNullOrWhiteSpace([string]$themeConfiguration.Theme.Source)) {
    throw "The JSON file does not contain the detected theme source."
}

#
# Retrieve the currently connected site.
#

$currentWeb = Get-PnPWeb -Includes PrimaryColor

$exportedSiteUrl = ([string]$themeConfiguration.Site.Url).TrimEnd('/')
$currentSiteUrl = ([string]$currentWeb.Url).TrimEnd('/')

$siteUrlsMatch = $exportedSiteUrl.Equals(
    $currentSiteUrl,
    [System.StringComparison]::OrdinalIgnoreCase
)

if (-not $siteUrlsMatch -and -not $IgnoreSiteUrlMismatch) {
    throw (
        "The connected site does not match the site recorded in the export file. " +
        "Connected site: '{0}'. Exported site: '{1}'. " +
        "Use -IgnoreSiteUrlMismatch only if restoring this theme to a different site is intentional." -f
        $currentSiteUrl,
        $exportedSiteUrl
    )
}

$themeName = [string]$themeConfiguration.Theme.Name
$themeSource = [string]$themeConfiguration.Theme.Source

#
# Validate the detected source.
#

$supportedSources = @(
    'Microsoft'
    'Tenant'
)

if ($supportedSources -notcontains $themeSource) {
    throw (
        "The exported theme source is '{0}'. " +
        "Only themes identified as 'Microsoft' or 'Tenant' can be restored by name." -f
        $themeSource
    )
}

#
# For tenant themes, verify that the named theme still exists.
#

if ($themeSource -eq 'Tenant') {
    try {
        $tenantTheme = Get-PnPTenantTheme -Name $themeName `
            -ErrorAction Stop
    }
    catch {
        throw (
            "The tenant theme '{0}' could not be retrieved. " +
            "It may have been renamed, removed, or may not be accessible with the current connection. " +
            "{1}" -f
            $themeName,
            $_.Exception.Message
        )
    }

    if (-not $tenantTheme) {
        throw "The tenant theme '$themeName' no longer exists."
    }
}

#
# Apply the exported theme by name.
#

$targetDescription = "{0} [{1}]" -f $currentWeb.Url, $currentWeb.Title
$operation = "Restore the '$themeName' theme from source '$themeSource'"

if ($PSCmdlet.ShouldProcess($targetDescription, $operation)) {
    try {
        Set-PnPWebTheme `
            -Theme $themeName `
            -WebUrl $currentWeb.Url `
            -ErrorAction Stop
    }
    catch {
        throw (
            "Failed to restore theme '{0}' to '{1}'. {2}" -f
            $themeName,
            $currentWeb.Url,
            $_.Exception.Message
        )
    }

    #
    # Retrieve the site again to validate the resulting primary color.
    #

    $restoredWeb = Get-PnPWeb -Includes PrimaryColor

    $expectedPrimaryColor = [string]$themeConfiguration.Theme.PrimaryColor
    $actualPrimaryColor = [string]$restoredWeb.PrimaryColor
    $primaryColorMatches = $false

    if (
        -not [string]::IsNullOrWhiteSpace($expectedPrimaryColor) -and
        -not [string]::IsNullOrWhiteSpace($actualPrimaryColor)
    ) {
        $primaryColorMatches = $expectedPrimaryColor.Equals(
            $actualPrimaryColor,
            [System.StringComparison]::OrdinalIgnoreCase
        )
    }

    [PSCustomObject][ordered]@{
        SiteUrl              = $restoredWeb.Url
        SiteTitle            = $restoredWeb.Title
        ThemeName            = $themeName
        ThemeSource          = $themeSource
        ExpectedPrimaryColor = $expectedPrimaryColor
        ActualPrimaryColor   = $actualPrimaryColor
        PrimaryColorMatches  = $primaryColorMatches
        RestoredFrom         = (Resolve-Path -LiteralPath $Path).Path
        RestoredAtUtc        = [DateTime]::UtcNow.ToString('o')
    }
}