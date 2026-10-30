@EndUserText.label: 'SCE Buildable Material'
@AccessControl.authorizationCheck: #CHECK
@Search.searchable: true
define view entity ZC_SCEBuildableMaterial
  as select from ZI_SCEBuildableMaterial
{
      @UI.hidden: true
  key DivisionUUID,
      @EndUserText.label: 'Material'
      @UI.selectionField: [{ position: 20 }]
  key cast( Material as abap.char(28) )     as Material,
      // HANA refuses CONTAINS on a cast column (SQL code 7, dump on $search), so search the uncast copy
      @UI.hidden: true
      @Search.defaultSearchElement: true
      ZI_SCEBuildableMaterial.Material      as MaterialName,
      // ponytail: shorter types only so Fiori's computed column widths fit the fixed 1080px F4 dialog;
      // ingest/test_live_bot.py guards that materials.csv values still fit (matnr <= 28, tech names <= 16)
      @EndUserText.label: 'Category'
      @UI.selectionField: [{ position: 30 }]
      Category,
      @EndUserText.label: 'Minerals'
      cast( MineralCost as abap.int2 )      as MineralCost,
      @EndUserText.label: 'Gas'
      cast( GasCost as abap.int2 )          as GasCost,
      @EndUserText.label: 'Supply'
      cast( SupplyCost as abap.int2 )       as SupplyCost,
      @EndUserText.label: 'Produced by'
      cast( ProducedBy as abap.char(16) )   as ProducedBy,
      @EndUserText.label: 'Requires'
      cast( Prerequisite as abap.char(16) ) as Prerequisite,
      @UI.hidden: true
      MineralsOnHand,
      @UI.hidden: true
      GasOnHand,
      @UI.hidden: true
      ProducerOnHand,
      @UI.hidden: true
      PrerequisiteOnHand,
      @EndUserText.label: 'Buildable'
      @UI.selectionField: [{ position: 10 }]
      Buildable
}
