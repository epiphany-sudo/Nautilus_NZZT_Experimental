<h1 align="center">

Nautilus NZZT Experimental Source

---

<img src="images/banner.png" alt="image" width="1200">

</h1> 

Nautilus is a lightweight and free tool that using PowerShell that allows you to strip down your Windows ISOs easily. NZZT is the next fork that heavily based on [Nautilus](https://github.com/PastelPinkLab/Nautilus) and [tiny11maker](https://github.com/ntdevlabs/tiny11builder). Compatible with Windows 10/11 and LTSC (Long-term Servicing Channel)

## ⚠️ Disclaimer

> [!Warning]
> Great care went into making sure this script does not unintentionally break any OS functionality, but use at your own risk! This script modifies core system images offline. Always test your generated ISO on a Virtual Machine before deploying it on your main hardware.

> This script in this repo is experimental, if you're looking the main repo, take a look at this [link](https://github.com/PastelPinkLab/Nautilus_NZZT)

## What things will be removed (Scanned in Windows 11 26H2)

#### APPXs
- Clipchamp.Clipchamp
- Microsoft.ApplicationCompatibilityEnhancements
- Microsoft.BingNews
- Microsoft.BingSearch
- Microsoft.BingWeather
- Microsoft.GamingApp
- Microsoft.GetHelp
- Microsoft.MicrosoftOfficeHub
- Microsoft.MicrosoftSolitaireCollection
- Microsoft.MicrosoftStickyNotes
- Microsoft.OutlookForWindows
- Microsoft.Paint
- Microsoft.PowerAutomateDesktop
- Microsoft.ScreenSketch
- Microsoft.Todos
- Microsoft.Windows.DevHome
- Microsoft.Windows.Photos
- Microsoft.WindowsAlarms
- Microsoft.WindowsCalculator
- Microsoft.WindowsCamera
- Microsoft.WindowsFeedbackHub
- Microsoft.WindowsNotepad
- Microsoft.WindowsSoundRecorder
- Microsoft.WindowsStore
- Microsoft.WindowsTerminal
- Microsoft.Xbox.TCUI
- Microsoft.XboxGamingOverlay
- Microsoft.XboxIdentityProvider
- Microsoft.XboxSpeechToTextOverlay
- Microsoft.YourPhone
- Microsoft.ZuneMusic
- MicrosoftCorporationII.QuickAssist
- MicrosoftWindows.Client.WebExperience
- MicrosoftWindows.CrossDevice
- MSTeams

#### Optional Features (Unlocked DMA Region Policy)
- Printing-Foundation-InternetPrinting-Client
- Printing-XPSServices-Features
- Printing-PrintToPDFServices-Features
- WorkFolders-Client
- MediaPlayback
- SMB1Protocol
- SMB1Protocol-Client
- SMB1Protocol-Server
- SMB1Protocol-Deprecation
- MSRDC-Infrastructure

#### Capabilities (FOD)
- App.StepsRecorder
- Browser.InternetExplorer
- Language.Handwriting
- Language.OCR
- Language.Speech
- Language.TextToSpeech
- MathRecognizer
- Microsoft.Wallpapers.Extended
- Microsoft.Windows.PowerShell.ISE
- OneCoreUAP.OneSync
- Print.Management.Console
- VBSCRIPT

#### CBS Package
- Microsoft-Copilot-Package
- Microsoft-Windows-CEIPEnable-Adm-Package
- Microsoft-Windows-FlipGridPWA-Package
- Microsoft-Windows-Internet-Browser-Package
- Microsoft-Windows-OneDrive-Setup-Package
- Microsoft-Windows-OneDrive-Setup-WOW64-Package
- Microsoft-Windows-OutlookPWA-Package
- Microsoft-Windows-Printing-XpsDocumentWriter-Opt-Package
- Microsoft-Windows-Printing-XPSServices-Package
- Microsoft-Windows-RemoteAssistance-Package-Client
- UserExperience-AIX-Package
- LanguageFeatures-TextToSpeech
- UserExperience-Recall-Package

#### And more...
- Edge (Edge, EdgeUpdate, EdgeCore)
- Microsoft-Edge-Webview
- OneDrive

## Tweaks
- Telemetry, sponsors apps
- Disable Copilot
- GameDXR and Xbox
- Enable Local Accounts
- Disable Bing
- Disable ContentDelivery
- Disable Bitlocker
- Bypass TPM 2.0 and unsupported CPU
- Disable HR and Hibernation
- ResetBase

## So... how to use the builder?

### Requirements
- A pure Windows 11 ISO downloaded from Microsoft.
- At least 20GB of free space on your `C:\` drive for the workspace.
- **Administrator Privileges** (The script will automatically check for this).

### Running the Script

1. Download the latest version of the script (`NautilusBuilder.ps1`).
2. Open PowerShell as Administrator.
3. Temporarily allow script execution by running:
   ```PowerShell
   Set-ExecutionPolicy Unrestricted -Scope Process -Force
4. Follow the instructions
5. Sit back and let the tool do it

## License
Nautilus is licensed under the GPLv3 license. See the LICENSE file for more information.

## Credits
- [NTDEV](https://github.com/ntdevlabs) for creating and hosting Tiny11Builder
- [Luu Phuong](https://github.com/lyghtlychee) for providing some neccessary infos
- [Raphire](https://github.com/Raphire) for Win11Debloat
- ...

## Support me
- Non-available, unfortunately
