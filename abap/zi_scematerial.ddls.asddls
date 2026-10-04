@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'SCE Material'
define root view entity ZI_SCEMaterial
  as select from zsce_material
{
  key material_uuid as MaterialUUID,
      matnr         as Material,
      bukrs         as CompanyCode,
      category      as Category,
      mineral_cost  as MineralCost,
      gas_cost      as GasCost,
      supply_cost   as SupplyCost,
      supply_provided as SupplyProvided,
      build_seconds as BuildSeconds,
      produced_by   as ProducedBy,
      prerequisite  as Prerequisite,
      @Semantics.systemDateTime.lastChangedAt: true
      last_changed_at as LastChangedAt
}
