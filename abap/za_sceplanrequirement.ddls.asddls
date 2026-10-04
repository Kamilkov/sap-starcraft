@EndUserText.label: 'SCE Plan Requirement Parameters'
define abstract entity ZA_SCEPlanRequirement
{
  @UI.hidden: true
  DivisionUUID : sysuuid_x16;
  @EndUserText.label: 'Material'
  @Consumption.valueHelpDefinition: [{ entity: { name: 'ZC_SCEBuildableMaterial', element: 'Material' },
                                       additionalBinding: [{ localElement: 'DivisionUUID', element: 'DivisionUUID', usage: #FILTER }] }]
  Material : abap.char(40);
  @EndUserText.label: 'Quantity'
  Quantity : abap.int4;
  @EndUserText.label: 'Due at minute'
  DueMinute : abap.int4;
}
