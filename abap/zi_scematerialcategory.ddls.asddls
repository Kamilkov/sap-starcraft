@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'SCE Material category per material'
define view entity ZI_SCEMaterialCategory
  as select from zsce_material
{
      // grouped: zsce_material is keyed by a UUID, so a material stored twice must not multiply a join on it
  key matnr           as Material,
      max( category ) as Category
}
group by
  matnr
