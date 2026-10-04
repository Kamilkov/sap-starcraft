@EndUserText.label: 'SCE Release Order Parameters'
define abstract entity ZA_SCEReleaseOrder
{
  @UI.hidden: true
  DivisionUUID : sysuuid_x16;
  @EndUserText.label: 'Material'
  @Consumption.valueHelpDefinition: [{ entity: { name: 'ZC_SCEBuildableMaterial', element: 'Material' },
                                       additionalBinding: [{ localElement: 'DivisionUUID', element: 'DivisionUUID', usage: #FILTER }] }]
  Material : abap.char(40);
  @EndUserText.label: 'Quantity'
  Quantity : abap.int4;
  @EndUserText.label: 'Also order missing prerequisites'
  WithPrerequisites : abap_boolean;
}
