"! @testing ZI_SCEMOVEMENTANALYSIS
CLASS zcl_sce_analysis_test DEFINITION PUBLIC FINAL CREATE PUBLIC
  FOR TESTING DURATION SHORT RISK LEVEL HARMLESS.
  PRIVATE SECTION.
    CONSTANTS old_game   TYPE sysuuid_x16 VALUE 'A1000000000000000000000000000001'.
    CONSTANTS new_game   TYPE sysuuid_x16 VALUE 'A2000000000000000000000000000002'.
    CONSTANTS old_div    TYPE sysuuid_x16 VALUE 'D1000000000000000000000000000001'.
    CONSTANTS new_div    TYPE sysuuid_x16 VALUE 'D2000000000000000000000000000002'.
    CONSTANTS main_plant TYPE sysuuid_x16 VALUE 'F1000000000000000000000000000001'.
    CONSTANTS opening    TYPE sysuuid_x16 VALUE 'E0000000000000000000000000000001'.
    CONSTANTS mined_59   TYPE sysuuid_x16 VALUE 'E0000000000000000000000000000002'.
    CONSTANTS receipt_60 TYPE sysuuid_x16 VALUE 'E0000000000000000000000000000003'.
    CONSTANTS consumed   TYPE sysuuid_x16 VALUE 'E0000000000000000000000000000004'.
    CONSTANTS reversed   TYPE sysuuid_x16 VALUE 'E0000000000000000000000000000005'.
    CONSTANTS lost       TYPE sysuuid_x16 VALUE 'E0000000000000000000000000000006'.
    CONSTANTS old_mined  TYPE sysuuid_x16 VALUE 'E0000000000000000000000000000007'.
    CONSTANTS mystery    TYPE sysuuid_x16 VALUE 'E0000000000000000000000000000008'.
    CLASS-DATA env TYPE REF TO if_cds_test_environment.
    CLASS-METHODS class_setup.
    CLASS-METHODS class_teardown.
    METHODS setup.
    METHODS minute_from_game_seconds FOR TESTING.
    METHODS movement_type_texts FOR TESTING.
    METHODS only_newest_game_is_latest FOR TESTING.
    METHODS game_player_race_joined FOR TESTING.
    METHODS amounts_pass_through FOR TESTING.
    METHODS unknown_material_is_kept FOR TESTING.
ENDCLASS.

CLASS zcl_sce_analysis_test IMPLEMENTATION.
  METHOD class_setup.
    " base dependencies: ZI_SCELATESTGAME is evaluated on the doubled ZSCE_GAME, so max( created_at ) is tested too
    env = cl_cds_test_environment=>create( i_for_entity = 'ZI_SCEMOVEMENTANALYSIS' i_select_base_dependencies = abap_true ).
  ENDMETHOD.

  METHOD class_teardown.
    env->destroy( ).
  ENDMETHOD.

  METHOD setup.
    DATA games TYPE STANDARD TABLE OF zsce_game WITH EMPTY KEY.
    DATA divisions TYPE STANDARD TABLE OF zsce_division WITH EMPTY KEY.
    DATA companies TYPE STANDARD TABLE OF zsce_company WITH EMPTY KEY.
    DATA plants TYPE STANDARD TABLE OF zsce_plant WITH EMPTY KEY.
    DATA materials TYPE STANDARD TABLE OF zsce_material WITH EMPTY KEY.
    DATA events TYPE STANDARD TABLE OF zsce_event WITH EMPTY KEY.
    env->clear_doubles( ).
    games = VALUE #( ( game_uuid = old_game map_name = 'Void Training Stage 1' played_at = '20260922120000.0000000'
                       created_at = '20260922130000.0000000' )
                     ( game_uuid = new_game map_name = 'AcropolisLE' played_at = '20260925112644.0000000'
                       created_at = '20260925112650.0000000' ) ).
    divisions = VALUE #( ( division_uuid = old_div game_uuid = old_game bukrs = '1000' player_name = 'Kamil' )
                         ( division_uuid = new_div game_uuid = new_game bukrs = '1000' player_name = 'SAP Outpost' ) ).
    companies = VALUE #( ( company_uuid = 'C1000000000000000000000000000001' bukrs = '1000' race = 'Terran' ) ).
    plants = VALUE #( ( plant_uuid = main_plant division_uuid = new_div plant_code = '0001' ) ).
    materials = VALUE #( ( material_uuid = 'B0000000000000000000000000000001' matnr = 'Marauder' category = 'UNIT' ) ).
    events = VALUE #( ( event_uuid = opening    division_uuid = new_div mvt_type = '561' matnr = 'MINERAL'
                        game_seconds = 0  quantity = 50  mineral_value = 50 )
                      ( event_uuid = mined_59   division_uuid = new_div mvt_type = '501' matnr = 'MINERAL'
                        game_seconds = 59 quantity = 80  mineral_value = 80 )
                      ( event_uuid = receipt_60 division_uuid = new_div plant_uuid = main_plant mvt_type = '101'
                        matnr = 'Marauder' game_seconds = 60 quantity = 1 mineral_value = 100 gas_value = 25
                        event_source = 'LIVE' )
                      ( event_uuid = consumed   division_uuid = new_div mvt_type = '261' matnr = 'MINERAL'
                        game_seconds = 61 quantity = 150 mineral_value = 150 )
                      ( event_uuid = reversed   division_uuid = new_div mvt_type = '262' matnr = 'MINERAL'
                        game_seconds = 62 quantity = 113 mineral_value = 113 )
                      ( event_uuid = lost       division_uuid = new_div mvt_type = '551' matnr = 'Marauder'
                        game_seconds = 125 quantity = 1 mineral_value = 100 gas_value = 25 )
                      ( event_uuid = old_mined  division_uuid = old_div mvt_type = '501' matnr = 'MINERAL'
                        game_seconds = 30 quantity = 40  mineral_value = 40 )
                      ( event_uuid = mystery    division_uuid = new_div mvt_type = '561' matnr = 'Mystery'
                        game_seconds = 0  quantity = 1   mineral_value = 30 ) ).
    env->insert_test_data( i_data = games ).
    env->insert_test_data( i_data = divisions ).
    env->insert_test_data( i_data = companies ).
    env->insert_test_data( i_data = plants ).
    env->insert_test_data( i_data = materials ).
    env->insert_test_data( i_data = events ).
  ENDMETHOD.

  METHOD minute_from_game_seconds.
    SELECT SINGLE gameminute FROM zi_scemovementanalysis WHERE eventuuid = @mined_59 INTO @DATA(at_59).
    SELECT SINGLE gameminute FROM zi_scemovementanalysis WHERE eventuuid = @receipt_60 INTO @DATA(at_60).
    SELECT SINGLE gameminute FROM zi_scemovementanalysis WHERE eventuuid = @lost INTO @DATA(at_125).
    cl_abap_unit_assert=>assert_equals( act = at_59 exp = 0 msg = '59 s is still minute 0' ).
    cl_abap_unit_assert=>assert_equals( act = at_60 exp = 1 msg = '60 s starts minute 1' ).
    cl_abap_unit_assert=>assert_equals( act = at_125 exp = 2 ).
  ENDMETHOD.

  METHOD movement_type_texts.
    TYPES: BEGIN OF ty_text, movementtype TYPE zsce_event-mvt_type, movementtypetext TYPE c LENGTH 20, END OF ty_text.
    DATA expected TYPE STANDARD TABLE OF ty_text WITH EMPTY KEY.
    SELECT DISTINCT movementtype, movementtypetext FROM zi_scemovementanalysis
      ORDER BY movementtype INTO TABLE @DATA(texts).
    expected = VALUE #( ( movementtype = '101' movementtypetext = 'Receipt (101)' )
                        ( movementtype = '261' movementtypetext = 'Consumption (261)' )
                        ( movementtype = '262' movementtypetext = 'Reversal (262)' )
                        ( movementtype = '501' movementtypetext = 'Mining (501)' )
                        ( movementtype = '551' movementtypetext = 'Loss (551)' )
                        ( movementtype = '561' movementtypetext = 'Opening stock (561)' ) ).
    cl_abap_unit_assert=>assert_equals( act = lines( texts ) exp = 6 ).
    LOOP AT expected INTO DATA(row).
      cl_abap_unit_assert=>assert_equals( act = texts[ movementtype = row-movementtype ]-movementtypetext
                                          exp = row-movementtypetext ).
    ENDLOOP.
  ENDMETHOD.

  METHOD only_newest_game_is_latest.
    SELECT SINGLE latestgame FROM zi_scemovementanalysis WHERE eventuuid = @receipt_60 INTO @DATA(newest).
    SELECT SINGLE latestgame FROM zi_scemovementanalysis WHERE eventuuid = @old_mined INTO @DATA(older).
    cl_abap_unit_assert=>assert_equals( act = newest exp = 'Yes' msg = 'the newest created game is the latest' ).
    cl_abap_unit_assert=>assert_equals( act = older exp = 'No' ).
  ENDMETHOD.

  METHOD game_player_race_joined.
    SELECT SINGLE gameuuid, mapname, playeddate, playedtime, playername, companycode, race, plantcode
      FROM zi_scemovementanalysis WHERE eventuuid = @receipt_60 INTO @DATA(row).
    cl_abap_unit_assert=>assert_equals( act = row-gameuuid exp = new_game ).
    cl_abap_unit_assert=>assert_equals( act = row-mapname exp = 'AcropolisLE' ).
    cl_abap_unit_assert=>assert_equals( act = row-playeddate exp = '20260925' msg = 'played-at date, UTC' ).
    cl_abap_unit_assert=>assert_equals( act = row-playedtime exp = '112644' msg = 'played-at time, UTC' ).
    cl_abap_unit_assert=>assert_equals( act = row-playername exp = 'SAP Outpost' ).
    cl_abap_unit_assert=>assert_equals( act = row-companycode exp = '1000' ).
    cl_abap_unit_assert=>assert_equals( act = row-race exp = 'Terran' ).
    cl_abap_unit_assert=>assert_equals( act = row-plantcode exp = '0001' ).
    SELECT SINGLE gamename FROM zi_scemovementanalysis WHERE eventuuid = @receipt_60 INTO @DATA(game_name).
    cl_abap_unit_assert=>assert_equals( act = game_name exp = 'AcropolisLE 2026-09-25 11:26' msg = 'map, played-at date and time (UTC)' ).
    SELECT SINGLE plantcode FROM zi_scemovementanalysis WHERE eventuuid = @mined_59 INTO @DATA(no_plant).
    cl_abap_unit_assert=>assert_initial( act = no_plant msg = 'division-level postings keep their row, without outpost' ).
  ENDMETHOD.

  METHOD amounts_pass_through.
    SELECT SINGLE quantity, minerals, mineralcurrency, gas, gascurrency, category, eventsource
      FROM zi_scemovementanalysis WHERE eventuuid = @receipt_60 INTO @DATA(row).
    cl_abap_unit_assert=>assert_equals( act = row-quantity exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = CONV i( row-minerals ) exp = 100 ).
    cl_abap_unit_assert=>assert_equals( act = row-mineralcurrency exp = 'MIN' ).
    cl_abap_unit_assert=>assert_equals( act = CONV i( row-gas ) exp = 25 ).
    cl_abap_unit_assert=>assert_equals( act = row-gascurrency exp = 'GAS' ).
    cl_abap_unit_assert=>assert_equals( act = row-category exp = 'UNIT' ).
    cl_abap_unit_assert=>assert_equals( act = row-eventsource exp = 'LIVE' ).
  ENDMETHOD.

  METHOD unknown_material_is_kept.
    SELECT SINGLE category, minerals FROM zi_scemovementanalysis WHERE eventuuid = @mystery INTO @DATA(row).
    cl_abap_unit_assert=>assert_subrc( exp = 0 msg = 'an unknown material must not drop the event' ).
    cl_abap_unit_assert=>assert_initial( act = row-category ).
    cl_abap_unit_assert=>assert_equals( act = CONV i( row-minerals ) exp = 30 ).
    SELECT COUNT( * ) FROM zi_scemovementanalysis INTO @DATA(total).
    cl_abap_unit_assert=>assert_equals( act = total exp = 8 msg = 'one row per event, no join doubles or drops' ).
  ENDMETHOD.
ENDCLASS.

