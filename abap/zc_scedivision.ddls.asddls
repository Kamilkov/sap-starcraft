@EndUserText.label: 'SCE Division'
@AccessControl.authorizationCheck: #CHECK
@Metadata.allowExtensions: true
@UI.headerInfo: { typeName: 'Division', typeNamePlural: 'Divisions', title: { value: 'PlayerName' }, description: { value: 'CompanyCode' } }
define view entity ZC_SCEDivision
  as projection on ZI_SCEDivision
  association [0..*] to ZC_SCEDivisionFinance as _Finance      on _Finance.DivisionUUID = $projection.DivisionUUID
  association [0..*] to ZC_SCEPlantFinance    as _PlantFinance on _PlantFinance.DivisionUUID = $projection.DivisionUUID
  // PM: read-only views on the ledger; their sections on the page come with the Fiori stage
  association [0..*] to ZC_SCEEquipment       as _Equipment    on _Equipment.DivisionUUID = $projection.DivisionUUID
  association [0..*] to ZC_SCESerialNumber    as _SerialNumber on _SerialNumber.DivisionUUID = $projection.DivisionUUID
{
      @UI.facet: [{ id: 'PostureHeader', purpose: #HEADER, type: #DATAPOINT_REFERENCE, targetQualifier: 'Posture', position: 1 },
                  { id: 'Finance',      type: #PRESENTATIONVARIANT_REFERENCE, targetElement: '_Finance',      targetQualifier: 'ByPlayer', label: 'Finance',           position: 5 },
                  { id: 'Plants',       type: #LINEITEM_REFERENCE,            targetElement: '_Plant',                                     label: 'Outposts',          position: 10 },
                  { id: 'PlantFinance', type: #PRESENTATIONVARIANT_REFERENCE, targetElement: '_PlantFinance', targetQualifier: 'ByPlant',  label: 'Outpost finance',   position: 15 },
                  { id: 'Orders',       type: #LINEITEM_REFERENCE,            targetElement: '_ProdOrder',                                 label: 'Production Orders', position: 20 },
                  { id: 'Requirements', type: #PRESENTATIONVARIANT_REFERENCE, targetElement: '_Requirement',  targetQualifier: 'ByDue',    label: 'Planned Requirements', position: 22 },
                  { id: 'PlannedOrders', type: #PRESENTATIONVARIANT_REFERENCE, targetElement: '_PlannedOrder', targetQualifier: 'ByStart', label: 'Planned Orders',   position: 24 },
                  { id: 'Movements',    type: #LINEITEM_REFERENCE,            targetElement: '_Event',                                     label: 'Goods Movements',   position: 30 },
                  // PM (spec 2026-09-27): equipment after the outposts, notifications and repair orders after production, serial numbers last
                  { id: 'Equipment',     type: #PRESENTATIONVARIANT_REFERENCE, targetElement: '_Equipment',    targetQualifier: 'ByReceipt',  label: 'Equipment',                 position: 12 },
                  { id: 'Notifications', type: #PRESENTATIONVARIANT_REFERENCE, targetElement: '_Notification', targetQualifier: 'ByPriority', label: 'Maintenance Notifications', position: 26 },
                  { id: 'MaintOrders',   type: #PRESENTATIONVARIANT_REFERENCE, targetElement: '_MaintOrder',   targetQualifier: 'ByPriority', label: 'Maintenance Orders',        position: 28 },
                  { id: 'SerialNumbers', type: #PRESENTATIONVARIANT_REFERENCE, targetElement: '_SerialNumber', targetQualifier: 'ByReceipt',  label: 'Serial Numbers',            position: 40 }]
  key DivisionUUID,
      GameUUID,
      @UI.lineItem: [{ position: 10 }]
      CompanyCode,
      @UI.lineItem: [{ position: 20 }]
      DivisionCode,
      @UI.lineItem: [{ position: 30 },
                     { type: #FOR_ACTION, dataAction: 'releaseOrder', label: 'Release Order' }]
      @UI.identification: [{ type: #FOR_ACTION, dataAction: 'releaseOrder', label: 'Release Order' },
                           { type: #FOR_ACTION, dataAction: 'planRequirement', label: 'Plan Requirement' },
                           { type: #FOR_ACTION, dataAction: 'runMrp', label: 'Run MRP' },
                           { type: #FOR_ACTION, dataAction: 'setPosture', label: 'Set Army Posture' }]
      PlayerName,
      @UI.lineItem: [{ position: 40 }]
      GameResult,
      // Part 2: the referee writes the game clock at every decision tick; MRP and the PIR defaults read it
      @EndUserText.label: 'Game clock (s)'
      @UI.lineItem: [{ position: 45, label: 'Game clock (s)' }]
      GameClock,
      // Part 2: ''/DEFEND or ATTACK; the bots poll it, setPosture is the only writer (ATTACK needs a 500 MIN army)
      @EndUserText.label: 'Army posture'
      @UI.lineItem: [{ position: 47, label: 'Army posture' }]
      @UI.dataPoint: { qualifier: 'Posture', title: 'Army posture' }
      ArmyPosture,
      _NetWorth.ReportingCurrency as ReportingCurrency,
      // B.2.1: minerals + gas at the TCURR rate M (GAS -> MIN), see ZI_SCEDivisionNetWorth
      @EndUserText.label: 'Net worth (MIN)'
      @UI.lineItem: [{ position: 50 }]
      @Semantics.amount.currencyCode: 'ReportingCurrency'
      _NetWorth.NetWorthMin       as NetWorthMin,
      _Game      : redirected to parent ZC_SCEGame,
      _Plant     : redirected to composition child ZC_SCEPlant,
      _ProdOrder : redirected to composition child ZC_SCEProdOrder,
      _Event     : redirected to composition child ZC_SCEEvent,
      _Requirement  : redirected to composition child ZC_SCEPIR,
      _PlannedOrder : redirected to composition child ZC_SCEPlannedOrder,
      _Notification : redirected to composition child ZC_SCENotification,
      _MaintOrder   : redirected to composition child ZC_SCEMaintOrder,
      _Company   : redirected to ZC_SCECompany,
      _Finance,
      _PlantFinance,
      _Equipment,
      _SerialNumber
}
