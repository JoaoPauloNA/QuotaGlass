"""Expose the installed macOS 27 blur ABI in a build-local SDK interface only."""
import pathlib, subprocess, sys
sdk = pathlib.Path(subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip())
version = subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-version'], text=True).strip()
if int(version.split('.')[0]) != 27:
    raise SystemExit('The private widget blur bridge requires the macOS 27 SDK; review its ABI before using another SDK.')
source = sdk / 'System/Library/Frameworks/WidgetKit.framework/Modules/WidgetKit.swiftmodule/arm64e-apple-macos.swiftinterface'
tbd = (sdk / 'System/Library/Frameworks/WidgetKit.framework/Versions/A/WidgetKit.tbd').read_text()
for symbol in ['$s7SwiftUI19WidgetConfigurationP0C3KitE24preferredBackgroundStyleyQrAD0cgH0OF', '$s9WidgetKit0A15BackgroundStyleO4bluryA2CmFWC']:
    if symbol not in tbd:
        raise SystemExit('Expected native blur symbol is missing; refusing to generate the bridge.')
text = source.read_text().replace('-target arm64e-apple-macos27.0', '-target arm64-apple-macos27.0').replace('-target-arch-variant arm64e.x1', '')
text += '''
// Private declarations discovered in the installed Batteries widget and SDK exports.
@available(macOS 27.0, *)
public enum WidgetBackgroundStyle {
  case opaque
  case transparent
  case blur
}
@available(macOS 27.0, *)
extension SwiftUI.WidgetConfiguration {
  @_Concurrency.MainActor @preconcurrency public func preferredBackgroundStyle(_ style: WidgetKit.WidgetBackgroundStyle) -> some SwiftUI.WidgetConfiguration
}
'''
destination = pathlib.Path(sys.argv[1]) / 'WidgetKit.swiftmodule/arm64-apple-macos.swiftinterface'
destination.parent.mkdir(parents=True, exist_ok=True)
destination.write_text(text)
