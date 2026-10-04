"! @testing ZI_SCEDIVISIONFINANCE
"! @testing ZI_SCEPLANTFINANCE
CLASS zcl_sce_finance_test DEFINITION PUBLIC FINAL CREATE PUBLIC
  FOR TESTING DURATION SHORT RISK LEVEL HARMLESS.
  PRIVATE SECTION.
    CONSTANTS d1 TYPE sysuuid_x16 VALUE 'D1D1D1D1D1D1D1D1D1D1D1D1D1D1D1D1'.
    CONSTANTS d2 TYPE sysuuid_x16 VALUE 'D2D2D2D2D2D2D2D2D2D2D2D2D2D2D2D2'.
    CONSTANTS d3 TYPE sysuuid_x16 VALUE 'D3D3D3D3D3D3D3D3D3D3D3D3D3D3D3D3'.
    CONSTANTS nobody TYPE sysuuid_x16 VALUE 'D4D4D4D4D4D4D4D4D4D4D4D4D4D4D4D4'.
    CONSTANTS d5 TYPE sysuuid_x16 VALUE 'D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5'.
    CONSTANTS m1 TYPE sysuuid_x16 VALUE 'C9C9C9C9C9C9C9C9C9C9C9C9C9C9C9C9'.
    CONSTANTS p1 TYPE sysuuid_x16 VALUE 'A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1'.
    CONSTANTS o1 TYPE sysuuid_x16 VALUE 'C1C1C1C1C1C1C1C1C1C1C1C1C1C1C1C1'.
    CONSTANTS o2 TYPE sysuuid_x16 VALUE 'C2C2C2C2C2C2C2C2C2C2C2C2C2C2C2C2'.
    CONSTANTS o3 TYPE sysuuid_x16 VALUE 'C3C3C3C3C3C3C3C3C3C3C3C3C3C3C3C3'.
    CONSTANTS o4 TYPE sysuuid_x16 VALUE 'C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4C4'.
    CONSTANTS o5 TYPE sysuuid_x16 VALUE 'C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5'.
    CONSTANTS o6 TYPE sysuuid_x16 VALUE 'C6C6C6C6C6C6C6C6C6C6C6C6C6C6C6C6'.
    CONSTANTS o7 TYPE sysuuid_x16 VALUE 'C7C7C7C7C7C7C7C7C7C7C7C7C7C7C7C7'.
    CONSTANTS o8 TYPE sysuuid_x16 VALUE 'C8C8C8C8C8C8C8C8C8C8C8C8C8C8C8C8'.
    CLASS-DATA env TYPE REF TO if_cds_test_environment.
    CLASS-METHODS class_setup.
    CLASS-METHODS class_teardown.
    METHODS setup.
    METHODS division_min FOR TESTING.
    METHODS division_gas FOR TESTING.
    METHODS divisions_stay_apart FOR TESTING.
    METHODS negative_wip_is_shown FOR TESTING.
    METHODS plant_figures FOR TESTING.
    METHODS networth_is_what_is_held FOR TESTING.
    METHODS maintenance_is_expense FOR TESTING.
    METHODS row_of IMPORTING division TYPE sysuuid_x16 currency TYPE waers
                   RETURNING VALUE(row) TYPE zi_scedivisionfinance.
ENDCLASS.

CLASS zcl_sce_finance_test IMPLEMENTATION.
  METHOD class_setup.
    " unit mode: both aggregates read one shared double of ZI_SCEEventAmount (the order status rides on its rows)
    env = cl_cds_test_environment=>create_for_multiple_cds(
            i_for_entities = VALUE #( ( i_for_entity = 'ZI_SCEDIVISIONFINANCE' )
                                      ( i_for_entity = 'ZI_SCEPLANTFINANCE' ) ) ).
  ENDMETHOD.

  METHOD class_teardown.
    env->destroy( ).
  ENDMETHOD.

  METHOD setup.
    DATA amounts TYPE STANDARD TABLE OF zi_sceeventamount WITH EMPTY KEY.
    env->clear_doubles( ).
    amounts = VALUE #(
      " D1 opening: Command Center, 2 SCVs, a material missing from the master (blank category), 50 minerals
      ( eventuuid = 'E0000000000000000000000000000001' currency = 'MIN' divisionuuid = d1 plantuuid = p1
        movementtype = '561' material = 'CommandCenter' category = 'STRUCTURE' amount = 400 )
      ( eventuuid = 'E0000000000000000000000000000002' currency = 'MIN' divisionuuid = d1 plantuuid = p1
        movementtype = '561' material = 'SCV' category = 'UNIT' amount = 50 )
      ( eventuuid = 'E0000000000000000000000000000003' currency = 'MIN' divisionuuid = d1 plantuuid = p1
        movementtype = '561' material = 'SCV' category = 'UNIT' amount = 50 )
      ( eventuuid = 'E0000000000000000000000000000004' currency = 'MIN' divisionuuid = d1 plantuuid = p1
        movementtype = '561' material = 'Mystery' category = '' amount = 30 )
      ( eventuuid = 'E0000000000000000000000000000005' currency = 'MIN' divisionuuid = d1
        movementtype = '561' material = 'MINERAL' category = 'RAW' amount = 50 )
      " D1 mining
      ( eventuuid = 'E0000000000000000000000000000006' currency = 'MIN' divisionuuid = d1
        movementtype = '501' material = 'MINERAL' category = 'RAW' amount = 500 )
      ( eventuuid = 'E0000000000000000000000000000007' currency = 'GAS' divisionuuid = d1
        movementtype = '501' material = 'VESPENE' category = 'RAW' amount = 120 )
      " D1 order O1: Marauder finished (100 MIN + 25 GAS)
      ( eventuuid = 'E0000000000000000000000000000008' currency = 'MIN' divisionuuid = d1 orderuuid = o1 orderstatus = 'CONFIRMED'
        movementtype = '261' material = 'MINERAL' category = 'RAW' amount = 100 )
      ( eventuuid = 'E0000000000000000000000000000009' currency = 'GAS' divisionuuid = d1 orderuuid = o1 orderstatus = 'CONFIRMED'
        movementtype = '261' material = 'VESPENE' category = 'RAW' amount = 25 )
      ( eventuuid = 'E0000000000000000000000000000010' currency = 'MIN' divisionuuid = d1 plantuuid = p1 orderuuid = o1
        orderstatus = 'CONFIRMED' movementtype = '101' material = 'Marauder' category = 'UNIT' amount = 100 )
      ( eventuuid = 'E0000000000000000000000000000010' currency = 'GAS' divisionuuid = d1 plantuuid = p1 orderuuid = o1
        orderstatus = 'CONFIRMED' movementtype = '101' material = 'Marauder' category = 'UNIT' amount = 25 )
      " D1 order O2: Barracks under construction (consumed, not received)
      ( eventuuid = 'E0000000000000000000000000000011' currency = 'MIN' divisionuuid = d1 orderuuid = o2 orderstatus = 'STARTED'
        movementtype = '261' material = 'MINERAL' category = 'RAW' amount = 150 )
      " D1 order O3: Marine built, then died
      ( eventuuid = 'E0000000000000000000000000000012' currency = 'MIN' divisionuuid = d1 orderuuid = o3 orderstatus = 'CONFIRMED'
        movementtype = '261' material = 'MINERAL' category = 'RAW' amount = 50 )
      ( eventuuid = 'E0000000000000000000000000000013' currency = 'MIN' divisionuuid = d1 plantuuid = p1 orderuuid = o3
        orderstatus = 'CONFIRMED' movementtype = '101' material = 'Marine' category = 'UNIT' amount = 50 )
      ( eventuuid = 'E0000000000000000000000000000014' currency = 'MIN' divisionuuid = d1 plantuuid = p1
        movementtype = '551' material = 'Marine' category = 'UNIT' amount = 50 )
      " D1 order O4: Supply Depot built, then destroyed (a structure: Assets and Lost move, Army must not)
      ( eventuuid = 'E0000000000000000000000000000017' currency = 'MIN' divisionuuid = d1 orderuuid = o4 orderstatus = 'CONFIRMED'
        movementtype = '261' material = 'MINERAL' category = 'RAW' amount = 100 )
      ( eventuuid = 'E0000000000000000000000000000018' currency = 'MIN' divisionuuid = d1 plantuuid = p1 orderuuid = o4
        orderstatus = 'CONFIRMED' movementtype = '101' material = 'SupplyDepot' category = 'STRUCTURE' amount = 100 )
      ( eventuuid = 'E0000000000000000000000000000019' currency = 'MIN' divisionuuid = d1 plantuuid = p1
        movementtype = '551' material = 'SupplyDepot' category = 'STRUCTURE' amount = 100 )
      " D1 order O5: the game refused the command; the bot reversed the 261 with a 262 (no WIP, nothing lost)
      ( eventuuid = 'E0000000000000000000000000000020' currency = 'MIN' divisionuuid = d1 orderuuid = o5 orderstatus = 'RELEASED'
        movementtype = '261' material = 'MINERAL' category = 'RAW' amount = 75 )
      ( eventuuid = 'E0000000000000000000000000000021' currency = 'MIN' divisionuuid = d1 orderuuid = o5 orderstatus = 'RELEASED'
        movementtype = '262' material = 'MINERAL' category = 'RAW' amount = 75 )
      " D1 order O6: Barracks cancelled under construction; SC2 gave back 113 of 150, the other 37 is scrap
      ( eventuuid = 'E0000000000000000000000000000022' currency = 'MIN' divisionuuid = d1 orderuuid = o6 orderstatus = 'CANCELLED'
        movementtype = '261' material = 'MINERAL' category = 'RAW' amount = 150 )
      ( eventuuid = 'E0000000000000000000000000000023' currency = 'MIN' divisionuuid = d1 orderuuid = o6 orderstatus = 'CANCELLED'
        movementtype = '262' material = 'MINERAL' category = 'RAW' amount = 113 )
      " D1 order O7: Supply Depot destroyed under construction: nothing back, all 100 is scrap
      ( eventuuid = 'E0000000000000000000000000000024' currency = 'MIN' divisionuuid = d1 orderuuid = o7 orderstatus = 'SCRAPPED'
        movementtype = '261' material = 'MINERAL' category = 'RAW' amount = 100 )
      " D1 order O8: TechLab died with its Barracks: 38 MIN + 19 GAS back, scrap 12 MIN + 6 GAS
      ( eventuuid = 'E0000000000000000000000000000025' currency = 'MIN' divisionuuid = d1 orderuuid = o8 orderstatus = 'SCRAPPED'
        movementtype = '261' material = 'MINERAL' category = 'RAW' amount = 50 )
      ( eventuuid = 'E0000000000000000000000000000026' currency = 'GAS' divisionuuid = d1 orderuuid = o8 orderstatus = 'SCRAPPED'
        movementtype = '261' material = 'VESPENE' category = 'RAW' amount = 25 )
      ( eventuuid = 'E0000000000000000000000000000027' currency = 'MIN' divisionuuid = d1 orderuuid = o8 orderstatus = 'SCRAPPED'
        movementtype = '262' material = 'MINERAL' category = 'RAW' amount = 38 )
      ( eventuuid = 'E0000000000000000000000000000028' currency = 'GAS' divisionuuid = d1 orderuuid = o8 orderstatus = 'SCRAPPED'
        movementtype = '262' material = 'VESPENE' category = 'RAW' amount = 19 )
      " D2: other division, mining only
      ( eventuuid = 'E0000000000000000000000000000015' currency = 'MIN' divisionuuid = d2
        movementtype = '501' material = 'MINERAL' category = 'RAW' amount = 999 )
      " D3: a receipt without an order and without an outpost (live bot could not match it)
      ( eventuuid = 'E0000000000000000000000000000016' currency = 'MIN' divisionuuid = d3
        movementtype = '101' material = 'Marine' category = 'UNIT' amount = 30 )
      " D5: a Barracks and 300 minerals at the start, 50 gas mined, then a repair (maintenance order M1) for 40 MIN + 13 GAS
      ( eventuuid = 'E0000000000000000000000000000030' currency = 'MIN' divisionuuid = d5
        movementtype = '561' material = 'MINERAL' category = 'RAW' amount = 300 )
      ( eventuuid = 'E0000000000000000000000000000031' currency = 'MIN' divisionuuid = d5
        movementtype = '561' material = 'Barracks' category = 'STRUCTURE' amount = 150 )
      ( eventuuid = 'E0000000000000000000000000000032' currency = 'GAS' divisionuuid = d5
        movementtype = '501' material = 'VESPENE' category = 'RAW' amount = 50 )
      ( eventuuid = 'E0000000000000000000000000000033' currency = 'MIN' divisionuuid = d5 orderuuid = m1 ordercategory = 'PM'
        movementtype = '261' material = 'MINERAL' category = 'RAW' amount = 40 )
      ( eventuuid = 'E0000000000000000000000000000034' currency = 'GAS' divisionuuid = d5 orderuuid = m1 ordercategory = 'PM'
        movementtype = '261' material = 'VESPENE' category = 'RAW' amount = 13 ) ).
    env->insert_test_data( i_data = amounts ).
  ENDMETHOD.

  METHOD row_of.
    SELECT SINGLE * FROM zi_scedivisionfinance
      WHERE divisionuuid = @division AND currency = @currency
      INTO CORRESPONDING FIELDS OF @row.
  ENDMETHOD.

  METHOD division_min.
    " Opening 400+50+50+30+50 = 580; Mined 500; Lost 50+100 = 150; Scrap O6 150-113 + O7 100 + O8 50-38 = 149
    " NetWorth 580+500-150-149 = 781
    " OnHand RAW 50+500-(100+150+50+100+75+150+100+50)+(75+113+38) = 1
    " Assets not-RAW (400+50+50+30)+(100+50+100)-(50+100) = 630
    " Army UNIT only (50+50)+(100+50)-50 = 200, the Supply Depot's 101/551 must not count
    " WIP (100+150+50+100+75)-75-(100+50+100) = 150 = the open Barracks; reversed O5 and scrapped O6-O8 add nothing
    cl_abap_unit_assert=>assert_equals(
      act = row_of( division = d1 currency = 'MIN' )
      exp = VALUE zi_scedivisionfinance( divisionuuid = d1 currency = 'MIN' opening = 580 mined = 500 lost = 150 scrap = 149
                                         networth = 781 onhand = 1 assets = 630 army = 200 wip = 150 ) ).
  ENDMETHOD.

  METHOD division_gas.
    " Mined 120; Scrap O8 25-19 = 6; NetWorth 120-6 = 114; OnHand 120-25-25+19 = 89; Assets = Army = 25; WIP 25-25 = 0
    cl_abap_unit_assert=>assert_equals(
      act = row_of( division = d1 currency = 'GAS' )
      exp = VALUE zi_scedivisionfinance( divisionuuid = d1 currency = 'GAS' opening = 0 mined = 120 lost = 0 scrap = 6
                                         networth = 114 onhand = 89 assets = 25 army = 25 wip = 0 ) ).
  ENDMETHOD.

  METHOD divisions_stay_apart.
    cl_abap_unit_assert=>assert_equals(
      act = row_of( division = d2 currency = 'MIN' )
      exp = VALUE zi_scedivisionfinance( divisionuuid = d2 currency = 'MIN' mined = 999 networth = 999 onhand = 999 ) ).
    SELECT COUNT( * ) FROM zi_scedivisionfinance WHERE divisionuuid = @nobody INTO @DATA(none).
    cl_abap_unit_assert=>assert_equals( act = none exp = 0 msg = 'a division without events has no rows' ).
  ENDMETHOD.

  METHOD negative_wip_is_shown.
    " ponytail: no clamp; negative WIP is the visible sign of a receipt without consumption
    cl_abap_unit_assert=>assert_equals(
      act = row_of( division = d3 currency = 'MIN' )
      exp = VALUE zi_scedivisionfinance( divisionuuid = d3 currency = 'MIN' assets = 30 army = 30 wip = -30 ) ).
  ENDMETHOD.

  METHOD plant_figures.
    " P1 MIN: Opening 400+50+50+30 = 530; Produced 100+50+100 = 250; Lost 50+100 = 150; NetAssetValue 630 (= D1 Assets)
    " P1 GAS: Produced 25; NetAssetValue 25. Events without an outpost (mining, consumption, D3) form no row.
    DATA rows TYPE STANDARD TABLE OF zi_sceplantfinance WITH EMPTY KEY.
    SELECT * FROM zi_sceplantfinance ORDER BY currency INTO CORRESPONDING FIELDS OF TABLE @rows.
    cl_abap_unit_assert=>assert_equals( act = lines( rows ) exp = 2 msg = 'only P1, one row per currency' ).
    cl_abap_unit_assert=>assert_equals(
      act = rows[ 1 ]
      exp = VALUE zi_sceplantfinance( plantuuid = p1 currency = 'GAS' divisionuuid = d1
                                      opening = 0 produced = 25 lost = 0 netassetvalue = 25 ) ).
    cl_abap_unit_assert=>assert_equals(
      act = rows[ 2 ]
      exp = VALUE zi_sceplantfinance( plantuuid = p1 currency = 'MIN' divisionuuid = d1
                                      opening = 530 produced = 250 lost = 150 netassetvalue = 630 ) ).
  ENDMETHOD.

  METHOD networth_is_what_is_held.
    " On hand + Assets + WIP = Opening + Mined - Lost - Scrap - Maintenance: scrap and maintenance must leave WIP and
    " Net worth together
    DATA held TYPE zi_scedivisionfinance-networth.
    SELECT * FROM zi_scedivisionfinance INTO TABLE @DATA(rows).
    LOOP AT rows INTO DATA(row).
      held = row-onhand + row-assets + row-wip.
      cl_abap_unit_assert=>assert_equals( act = held exp = row-networth
                                          msg = |identity broken for { row-divisionuuid } { row-currency }| ).
      held = row-opening + row-mined - row-lost - row-scrap - row-maintenance.
      cl_abap_unit_assert=>assert_equals( act = held exp = row-networth
                                          msg = |net worth formula broken for { row-divisionuuid } { row-currency }| ).
    ENDLOOP.
  ENDMETHOD.

  METHOD maintenance_is_expense.
    " a repair is expense at once: never WIP, off Net worth, the Barracks keeps its 150
    " MIN: Opening 300+150 = 450; Maintenance 40; NetWorth 410; OnHand 300-40 = 260; Assets 150; WIP 0
    cl_abap_unit_assert=>assert_equals(
      act = row_of( division = d5 currency = 'MIN' )
      exp = VALUE zi_scedivisionfinance( divisionuuid = d5 currency = 'MIN' opening = 450 maintenance = 40
                                         networth = 410 onhand = 260 assets = 150 wip = 0 ) ).
    " GAS: Mined 50; Maintenance 13; NetWorth 37 = OnHand
    cl_abap_unit_assert=>assert_equals(
      act = row_of( division = d5 currency = 'GAS' )
      exp = VALUE zi_scedivisionfinance( divisionuuid = d5 currency = 'GAS' mined = 50 maintenance = 13
                                         networth = 37 onhand = 37 ) ).
    " production is untouched by the new column
    cl_abap_unit_assert=>assert_equals( act = row_of( division = d1 currency = 'MIN' )-maintenance exp = 0 ).
  ENDMETHOD.
ENDCLASS.

