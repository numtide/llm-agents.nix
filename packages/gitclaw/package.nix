{
  lib,
  gitagent,
}:
lib.warnOnInstantiate "'gitclaw' has been renamed to 'gitagent'. Please update your references." gitagent
// {
  passthru = gitagent.passthru // {
    hideFromDocs = true;
    skipUpdate = true;
  };
}
