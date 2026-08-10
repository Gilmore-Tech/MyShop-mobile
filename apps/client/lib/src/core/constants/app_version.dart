/// Marketing version displayed inside release UI.
///
/// Production builds receive this from the same reviewed resolver that passes
/// Flutter's `--build-name`, preventing a signed binary from displaying
/// the obsolete 1.0.0 label.
const appMarketingVersion = String.fromEnvironment(
  'MYSHOP_MARKETING_VERSION',
  defaultValue: '1.4.5',
);

const appVersionLabel = 'Version $appMarketingVersion';
