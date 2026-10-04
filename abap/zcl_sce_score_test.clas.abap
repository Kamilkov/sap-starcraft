"! @testing ZI_SCESCORE
CLASS zcl_sce_score_test DEFINITION PUBLIC FINAL CREATE PUBLIC
  FOR TESTING DURATION SHORT RISK LEVEL HARMLESS.
  PRIVATE SECTION.
    CONSTANTS game  TYPE sysuuid_x16 VALUE 'A3000000000000000000000000000003'.
    CONSTANTS player TYPE sysuuid_x16 VALUE 'D3000000000000000000000000000003'.
    CONSTANTS rival  TYPE sysuuid_x16 VALUE 'D4000000000000000000000000000004'.
    CLASS-DATA env TYPE REF TO if_cds_test_environment.
    DATA grid TYPE STANDARD TABLE OF zi_scescoreminute WITH EMPTY KEY.
    DATA events TYPE STANDARD TABLE OF zi_scemovementanalysis WITH EMPTY KEY.
    DATA values TYPE STANDARD TABLE OF zi_scemovementvaluemin WITH EMPTY KEY.
    CLASS-METHODS class_setup.
    CLASS-METHODS class_teardown.
    METHODS setup.
    "! one goods movement of the game; its value in MIN at rate 2 (as OB08's rate M)
    METHODS add IMPORTING id       TYPE i
                          division TYPE sysuuid_x16
                          minute   TYPE i
                          mvt      TYPE zsce_event-mvt_type
                          material TYPE zsce_event-matnr
                          category TYPE zi_scemovementanalysis-category OPTIONAL
                          qty      TYPE i DEFAULT 1
                          minerals TYPE i DEFAULT 0
                          gas      TYPE i DEFAULT 0.
    METHODS score IMPORTING division   TYPE sysuuid_x16
                            minute     TYPE i
                  RETURNING VALUE(row) TYPE zi_scescore.
    METHODS army_counts_units_not_workers FOR TESTING.
    METHODS army_drops_with_losses FOR TESTING.
    METHODS workers_opening_trained_lost FOR TESTING.
    METHODS bank_signs FOR TESTING.
    METHODS collected_and_lost FOR TESTING.
    METHODS total_carries_over_gaps FOR TESTING.
    METHODS players_do_not_mix FOR TESTING.
ENDCLASS.

CLASS zcl_sce_score_test IMPLEMENTATION.
  METHOD class_setup.
    " direct dependencies doubled: keeps currency_conversion (inside ZI_SCEMovementValueMin) out of the test
    env = cl_cds_test_environment=>create( i_for_entity = 'ZI_SCESCORE' ).
  ENDMETHOD.

  METHOD class_teardown.
    env->destroy( ).
  ENDMETHOD.

  METHOD add.
    INSERT VALUE #( eventuuid    = CONV sysuuid_x16( |E{ id WIDTH = 31 ALIGN = RIGHT PAD = '0' }| )
                    gameuuid     = game
                    gamename     = 'AcropolisLE 2026-09-25 11:26'
                    latestgame   = 'Yes'
                    divisionuuid = division
                    playername   = COND #( WHEN division = player THEN 'SAP Outpost' ELSE 'Rival' )
                    companycode  = '1000'
                    race         = 'Terran'
                    gameminute   = minute
                    gameseconds  = minute * 60
                    movementtype = mvt
                    material     = material
                    category     = category
                    quantity     = qty
                    minerals     = minerals
                    gas          = gas ) INTO TABLE events.
    INSERT VALUE #( eventuuid = CONV sysuuid_x16( |E{ id WIDTH = 31 ALIGN = RIGHT PAD = '0' }| )
                    valuemin  = minerals + 2 * gas ) INTO TABLE values.
  ENDMETHOD.

  METHOD setup.
    env->clear_doubles( ).
    CLEAR: grid, events, values.
    " player: movements in minutes 0, 1 and 3; none in minute 2, so the grid has a gap there
    grid = VALUE #( ( divisionuuid = player gameminute = 0 )
                    ( divisionuuid = player gameminute = 1 )
                    ( divisionuuid = player gameminute = 3 )
                    ( divisionuuid = rival  gameminute = 0 ) ).
    add( id = 1  division = player minute = 0 mvt = '561' material = 'SCV'         category = 'UNIT'      qty = 8   minerals = 400 ).
    add( id = 2  division = player minute = 0 mvt = '561' material = 'MINERAL'     category = 'RAW'       qty = 50  minerals = 50 ).
    add( id = 3  division = player minute = 0 mvt = '501' material = 'MINERAL'     category = 'RAW'       qty = 100 minerals = 100 ).
    add( id = 4  division = player minute = 0 mvt = '501' material = 'VESPENE'     category = 'RAW'       qty = 50  gas = 50 ).
    add( id = 5  division = player minute = 1 mvt = '261' material = 'MINERAL'     category = 'RAW'       qty = 100 minerals = 100 ).
    add( id = 6  division = player minute = 1 mvt = '261' material = 'VESPENE'     category = 'RAW'       qty = 25  gas = 25 ).
    add( id = 7  division = player minute = 1 mvt = '101' material = 'Marauder'    category = 'UNIT'      minerals = 100 gas = 25 ).
    add( id = 8  division = player minute = 1 mvt = '101' material = 'SCV'         category = 'UNIT'      minerals = 50 ).
    add( id = 9  division = player minute = 1 mvt = '262' material = 'MINERAL'     category = 'RAW'       qty = 30  minerals = 30 ).
    add( id = 10 division = player minute = 3 mvt = '551' material = 'Marauder'    category = 'UNIT'      minerals = 100 gas = 25 ).
    add( id = 11 division = player minute = 3 mvt = '551' material = 'SCV'         category = 'UNIT'      minerals = 50 ).
    add( id = 12 division = player minute = 3 mvt = '551' material = 'SupplyDepot' category = 'STRUCTURE' minerals = 100 ).
    add( id = 13 division = player minute = 3 mvt = '551' material = 'Mystery'                            minerals = 30 ).
    add( id = 14 division = rival minute = 0 mvt = '561' material = 'SCV'      category = 'UNIT'      qty = 12  minerals = 600 ).
    add( id = 15 division = rival minute = 0 mvt = '501' material = 'MINERAL'  category = 'RAW'       qty = 999 minerals = 999 ).
    env->insert_test_data( i_data = grid ).
    env->insert_test_data( i_data = events ).
    env->insert_test_data( i_data = values ).
  ENDMETHOD.

  METHOD score.
    SELECT SINGLE * FROM zi_scescore WHERE divisionuuid = @division AND gameminute = @minute INTO @row.
    cl_abap_unit_assert=>assert_subrc( exp = 0 msg = |no score row for minute { minute }| ).
  ENDMETHOD.

  METHOD army_counts_units_not_workers.
    cl_abap_unit_assert=>assert_equals( act = CONV i( score( division = player minute = 0 )-armyvalue ) exp = 0
                                        msg = 'opening SCVs are workers, not army' ).
    cl_abap_unit_assert=>assert_equals( act = CONV i( score( division = player minute = 1 )-armyvalue ) exp = 150
                                        msg = 'a Marauder (100 + 2 x 25) counts, a trained SCV does not' ).
  ENDMETHOD.

  METHOD army_drops_with_losses.
    cl_abap_unit_assert=>assert_equals( act = CONV i( score( division = player minute = 3 )-armyvalue ) exp = 0
                                        msg = 'the lost Marauder leaves; lost SCV, structure and unknown material do not count' ).
  ENDMETHOD.

  METHOD workers_opening_trained_lost.
    cl_abap_unit_assert=>assert_equals( act = CONV i( score( division = player minute = 0 )-workers ) exp = 8 ).
    cl_abap_unit_assert=>assert_equals( act = CONV i( score( division = player minute = 1 )-workers ) exp = 9 ).
    cl_abap_unit_assert=>assert_equals( act = CONV i( score( division = player minute = 3 )-workers ) exp = 8 ).
  ENDMETHOD.

  METHOD bank_signs.
    cl_abap_unit_assert=>assert_equals( act = CONV i( score( division = player minute = 0 )-bankminerals ) exp = 150
                                        msg = 'opening 50 + mined 100' ).
    cl_abap_unit_assert=>assert_equals( act = CONV i( score( division = player minute = 0 )-bankgas ) exp = 50 ).
    cl_abap_unit_assert=>assert_equals( act = CONV i( score( division = player minute = 1 )-bankminerals ) exp = 80
                                        msg = '150 - consumed 100 + refunded 30' ).
    cl_abap_unit_assert=>assert_equals( act = CONV i( score( division = player minute = 1 )-bankgas ) exp = 25 ).
  ENDMETHOD.

  METHOD collected_and_lost.
    DATA(end) = score( division = player minute = 3 ).
    cl_abap_unit_assert=>assert_equals( act = CONV i( end-collected ) exp = 200 msg = 'mined 100 minerals + 50 gas x 2' ).
    cl_abap_unit_assert=>assert_equals( act = CONV i( end-lost ) exp = 330
                                        msg = 'Marauder 150 + SCV 50 + Supply Depot 100 + unknown material 30' ).
  ENDMETHOD.

  METHOD total_carries_over_gaps.
    DATA(after_gap) = score( division = player minute = 3 ).
    cl_abap_unit_assert=>assert_equals( act = CONV i( after_gap-bankminerals ) exp = 80
                                        msg = 'minute 3 carries minutes 0 and 1 across the missing minute 2' ).
    cl_abap_unit_assert=>assert_equals( act = CONV i( score( division = player minute = 1 )-collected ) exp = 200
                                        msg = 'minute 1 carries what minute 0 mined' ).
    SELECT COUNT( * ) FROM zi_scescore WHERE divisionuuid = @player INTO @DATA(rows).
    cl_abap_unit_assert=>assert_equals( act = rows exp = 3 msg = 'one row per grid minute' ).
  ENDMETHOD.

  METHOD players_do_not_mix.
    DATA(mine) = score( division = player minute = 0 ).
    DATA(theirs) = score( division = rival minute = 0 ).
    cl_abap_unit_assert=>assert_equals( act = CONV i( mine-workers ) exp = 8 ).
    cl_abap_unit_assert=>assert_equals( act = CONV i( mine-collected ) exp = 200 ).
    cl_abap_unit_assert=>assert_equals( act = CONV i( theirs-workers ) exp = 12 ).
    cl_abap_unit_assert=>assert_equals( act = CONV i( theirs-collected ) exp = 999 ).
    cl_abap_unit_assert=>assert_equals( act = mine-playername exp = 'SAP Outpost' ).
    cl_abap_unit_assert=>assert_equals( act = theirs-playername exp = 'Rival' ).
    cl_abap_unit_assert=>assert_equals( act = mine-gamename exp = 'AcropolisLE 2026-09-25 11:26' ).
  ENDMETHOD.
ENDCLASS.

