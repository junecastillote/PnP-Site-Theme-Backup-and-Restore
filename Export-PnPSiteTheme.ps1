[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Path
)

# Get the current web and its theme information.
$web = Get-PnPWeb -Includes PrimaryColor, ThemeInfo

$primaryColor = $web.PrimaryColor

# Documented SharePoint theme palette slots.
$paletteSlots = @(
    'themePrimary'
    'themeLighterAlt'
    'themeLighter'
    'themeLight'
    'themeTertiary'
    'themeSecondary'
    'themeDarkAlt'
    'themeDark'
    'themeDarker'
    'neutralLighterAlt'
    'neutralLighter'
    'neutralLight'
    'neutralQuaternaryAlt'
    'neutralQuaternary'
    'neutralTertiaryAlt'
    'neutralTertiary'
    'neutralSecondaryAlt'
    'neutralSecondary'
    'neutralPrimaryAlt'
    'neutralPrimary'
    'neutralDark'
    'black'
    'white'
    'primaryBackground'
    'primaryText'
    'bodyBackground'
    'bodyText'
    'disabledBackground'
    'disabledText'
    'error'
    'accent'
    'backgroundColor'
)

# Queue the theme shade requests.
$shadeResults = @{}

foreach ($slot in $paletteSlots) {
    $shadeResults[$slot] = $web.ThemeInfo.GetThemeShadeByName($slot)
}

# Execute all queued CSOM requests in one round trip.
$web.Context.ExecuteQuery()

# Build the palette object.
$palette = [ordered]@{}

foreach ($slot in $paletteSlots) {
    $palette[$slot] = $shadeResults[$slot].Value
}

#
# Theme identification
#

$themeName = $null
$themeSource = 'Unknown'

#
# 1. Check tenant/custom themes first.
#
# PnP exposes the name and palette of tenant themes, so these
# should take precedence over the static Microsoft lookup.
#

$tenantThemes = @(Get-PnPTenantTheme)

$tenantThemeMatch = $tenantThemes |
Where-Object {
    $_.Palette -and
    $_.Palette.themePrimary -and
    $_.Palette.themePrimary.Equals(
        $primaryColor,
        [System.StringComparison]::OrdinalIgnoreCase
    )
} |
Select-Object -First 1

if ($tenantThemeMatch) {
    $themeName = $tenantThemeMatch.Name
    $themeSource = 'Tenant'
}
else {

    #
    # 2. Check Microsoft's built-in themes.
    #
    # Values are based on Microsoft's published SharePoint
    # theme definitions.
    # Reference: https://learn.microsoft.com/en-us/sharepoint/dev/declarative-customization/site-theming/sharepoint-site-theming-json-schema
    #

    $microsoftThemes = @{
        '#007780' = 'Teal'
        '#1267B5' = 'Blue'
        '#A74411' = 'Orange'
        '#AD3A39' = 'Red'
        '#72559B' = 'Purple'
        '#437509' = 'Green'
        '#5B5D9B' = 'Periwinkle'
        '#355DCD' = 'Cobalt'
        '#51AEB2' = 'Dark Teal'
        '#529FF1' = 'Dark Blue'
    }

    $normalizedPrimaryColor = $primaryColor.ToUpperInvariant()

    if ($microsoftThemes.ContainsKey($normalizedPrimaryColor)) {
        $themeName = $microsoftThemes[$normalizedPrimaryColor]
        $themeSource = 'Microsoft'
    }
}

#
# Build export object.
#

$themeConfiguration = [ordered]@{
    ExportVersion = 1
    ExportedAtUtc = [DateTime]::UtcNow.ToString('o')

    Site          = [ordered]@{
        Title = $web.Title
        Url   = $web.Url
    }

    Theme         = [ordered]@{
        Name                  = $themeName
        Source                = $themeSource
        PrimaryColor          = $web.PrimaryColor
        AccessibleDescription = $web.ThemeInfo.AccessibleDescription
        BackgroundImageUri    = $web.ThemeInfo.ThemeBackgroundImageUri
        Palette               = $palette
    }
}

# Export the configuration.
$themeConfiguration |
ConvertTo-Json -Depth 10 |
Set-Content -Path $Path -Encoding UTF8

# Return the object for inspection/pipeline use.
[PSCustomObject]$themeConfiguration