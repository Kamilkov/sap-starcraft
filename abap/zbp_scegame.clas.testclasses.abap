CLASS ltc_validations DEFINITION FINAL FOR TESTING
  DURATION SHORT RISK LEVEL HARMLESS.
  PRIVATE SECTION.
    CLASS-DATA sql TYPE REF TO if_osql_test_environment.
    CLASS-METHODS class_setup.
    CLASS-METHODS class_teardown.
    METHODS setup.
    METHODS duplicate_replay_is_rejected FOR TESTING RAISING cx_static_check.
    METHODS unknown_mvt_type_is_rejected FOR TESTING RAISING cx_static_check.
    METHODS reversal_movement_is_accepted FOR TESTING RAISING cx_static_check.
    METHODS deep_create_fills_parent_keys FOR TESTING RAISING cx_static_check.
    METHODS release_order_creates_orders FOR TESTING RAISING cx_static_check.
    METHODS release_order_rejects_zero FOR TESTING RAISING cx_static_check.
    METHODS release_order_defaults FOR TESTING RAISING cx_static_check.
    METHODS buildable_reason_texts FOR TESTING.
ENDCLASS.

CLASS ltc_validations IMPLEMENTATION.
  METHOD class_setup.
    sql = cl_osql_test_environment=>create(
            VALUE #( ( 'ZSCE_GAME' ) ( 'ZSCE_DIVISION' ) ( 'ZSCE_PLANT' )
                     ( 'ZSCE_PRODORD' ) ( 'ZSCE_EVENT' ) ( 'ZSCE_MATERIAL' ) ) ).
  ENDMETHOD.

  METHOD class_teardown.
    sql->destroy( ).
  ENDMETHOD.

  METHOD setup.
    sql->clear_doubles( ).
    ROLLBACK ENTITIES.
  ENDMETHOD.

  METHOD duplicate_replay_is_rejected.
    DATA games TYPE STANDARD TABLE OF zsce_game WITH EMPTY KEY.
    games = VALUE #( ( game_uuid = '11111111111111111111111111111111' replay_hash = 'ABC' ) ).
    sql->insert_test_data( games ).

    MODIFY ENTITIES OF zi_scegame
      ENTITY game
        CREATE FIELDS ( gameuuid replayhash )
        WITH VALUE #( ( %cid = 'g1' gameuuid = '22222222222222222222222222222222' replayhash = 'ABC' ) )
      MAPPED DATA(mapped) FAILED DATA(failed) REPORTED DATA(reported).
    COMMIT ENTITIES RESPONSE OF zi_scegame
      FAILED DATA(commit_failed) REPORTED DATA(commit_reported).

    cl_abap_unit_assert=>assert_not_initial( act = commit_failed-game
                                             msg = 'duplicate replay hash must fail on save' ).
  ENDMETHOD.

  METHOD unknown_mvt_type_is_rejected.
    MODIFY ENTITIES OF zi_scegame
      ENTITY game
        CREATE FIELDS ( gameuuid replayhash )
        WITH VALUE #( ( %cid = 'g1' gameuuid = '33333333333333333333333333333333' replayhash = 'DEF' ) )
        CREATE BY \_Division FIELDS ( divisionuuid companycode divisioncode )
        WITH VALUE #( ( %cid_ref = 'g1'
                        %target  = VALUE #( ( %cid = 'd1' divisionuuid = '44444444444444444444444444444444'
                                              companycode = '1000' divisioncode = 'P1' ) ) ) )
      ENTITY division
        CREATE BY \_Event FIELDS ( eventuuid movementtype material quantity )
        WITH VALUE #( ( %cid_ref = 'd1'
                        %target  = VALUE #( ( %cid = 'e1' eventuuid = '55555555555555555555555555555555'
                                              movementtype = '999' material = 'SCV' quantity = 1 ) ) ) )
      MAPPED DATA(mapped) FAILED DATA(failed) REPORTED DATA(reported).
    COMMIT ENTITIES RESPONSE OF zi_scegame
      FAILED DATA(commit_failed) REPORTED DATA(commit_reported).

    cl_abap_unit_assert=>assert_not_initial( act = commit_failed-event
                                             msg = 'movement type 999 must fail on save' ).
  ENDMETHOD.

  METHOD reversal_movement_is_accepted.
    MODIFY ENTITIES OF zi_scegame
      ENTITY game
        CREATE FIELDS ( gameuuid replayhash )
        WITH VALUE #( ( %cid = 'g1' gameuuid = 'ADADADADADADADADADADADADADADADAD' replayhash = 'REVERSAL' ) )
        CREATE BY \_Division FIELDS ( divisionuuid companycode divisioncode )
        WITH VALUE #( ( %cid_ref = 'g1'
                        %target  = VALUE #( ( %cid = 'd1' divisionuuid = 'AEAEAEAEAEAEAEAEAEAEAEAEAEAEAEAE'
                                              companycode = '1000' divisioncode = 'P1' ) ) ) )
      ENTITY division
        CREATE BY \_Event FIELDS ( eventuuid movementtype material quantity mineralvalue )
        WITH VALUE #( ( %cid_ref = 'd1'
                        %target  = VALUE #( ( %cid = 'e1' eventuuid = 'AFAFAFAFAFAFAFAFAFAFAFAFAFAFAFAF'
                                              movementtype = '262' material = 'MINERAL'
                                              quantity = 50 mineralvalue = 50 ) ) ) )
      MAPPED DATA(mapped) FAILED DATA(failed) REPORTED DATA(reported).
    COMMIT ENTITIES RESPONSE OF zi_scegame
      FAILED DATA(commit_failed) REPORTED DATA(commit_reported).

    cl_abap_unit_assert=>assert_initial( act = commit_failed msg = '262 (reversal of a 261) must save' ).
  ENDMETHOD.

  METHOD deep_create_fills_parent_keys.
    MODIFY ENTITIES OF zi_scegame
      ENTITY game
        CREATE FIELDS ( gameuuid replayhash )
        WITH VALUE #( ( %cid = 'g1' gameuuid = '66666666666666666666666666666666' replayhash = 'GHI' ) )
        CREATE BY \_Division FIELDS ( divisionuuid companycode divisioncode )
        WITH VALUE #( ( %cid_ref = 'g1'
                        %target  = VALUE #( ( %cid = 'd1' divisionuuid = '77777777777777777777777777777777'
                                              companycode = '1000' divisioncode = 'P1' ) ) ) )
      ENTITY division
        CREATE BY \_Event FIELDS ( eventuuid movementtype material quantity )
        WITH VALUE #( ( %cid_ref = 'd1'
                        %target  = VALUE #( ( %cid = 'e1' eventuuid = '88888888888888888888888888888888'
                                              movementtype = '101' material = 'SCV' quantity = 1 ) ) ) )
      MAPPED DATA(mapped) FAILED DATA(failed) REPORTED DATA(reported).
    COMMIT ENTITIES RESPONSE OF zi_scegame
      FAILED DATA(commit_failed) REPORTED DATA(commit_reported).

    cl_abap_unit_assert=>assert_initial( act = commit_failed msg = 'valid deep create must save' ).
    SELECT SINGLE division_uuid FROM zsce_event
      WHERE event_uuid = '88888888888888888888888888888888' INTO @DATA(parent).
    cl_abap_unit_assert=>assert_equals( act = parent exp = '77777777777777777777777777777777'
                                        msg = 'RAP fills the child parent key' ).
  ENDMETHOD.

  METHOD release_order_creates_orders.
    DATA materials TYPE STANDARD TABLE OF zsce_material WITH EMPTY KEY.
    " Marine has a producer that is missing: without WithPrerequisites no Barracks order may appear
    materials = VALUE #( ( material_uuid = 'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC'
                           matnr = 'Marine' bukrs = '1000' category = 'UNIT' mineral_cost = 50 produced_by = 'Barracks' )
                         ( material_uuid = 'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCD'
                           matnr = 'Barracks' bukrs = '1000' category = 'STRUCTURE' mineral_cost = 150 produced_by = 'SCV' ) ).
    sql->insert_test_data( materials ).

    MODIFY ENTITIES OF zi_scegame
      ENTITY game
        CREATE FIELDS ( gameuuid replayhash )
        WITH VALUE #( ( %cid = 'g1' gameuuid = '99999999999999999999999999999999' replayhash = 'XYZ' ) )
        CREATE BY \_Division FIELDS ( divisionuuid companycode divisioncode )
        WITH VALUE #( ( %cid_ref = 'g1'
                        %target  = VALUE #( ( %cid = 'd1' divisionuuid = '88888888888888888888888888888888'
                                              companycode = '1000' divisioncode = 'P1' ) ) ) )
      MAPPED DATA(seed_mapped) FAILED DATA(seed_failed) REPORTED DATA(seed_reported).

    MODIFY ENTITIES OF zi_scegame
      ENTITY division
        EXECUTE releaseorder
          FROM VALUE #( ( divisionuuid = '88888888888888888888888888888888'
                          %param = VALUE #( material = 'Marine' quantity = 3 ) ) )
      FAILED DATA(failed) REPORTED DATA(reported).
    COMMIT ENTITIES RESPONSE OF zi_scegame
      FAILED DATA(commit_failed) REPORTED DATA(commit_reported).

    cl_abap_unit_assert=>assert_initial( act = failed-division msg = 'valid release must not fail' ).
    cl_abap_unit_assert=>assert_initial( act = commit_failed msg = 'release must save' ).
    SELECT COUNT( * ) FROM zsce_prodord
      WHERE division_uuid = '88888888888888888888888888888888'
        AND order_status  = 'RELEASED'
        AND matnr         = 'Marine'
      INTO @DATA(released).
    cl_abap_unit_assert=>assert_equals( act = released exp = 3 msg = 'quantity 3 = three orders of 1' ).
    SELECT COUNT( DISTINCT order_uuid ) FROM zsce_prodord
      WHERE division_uuid = '88888888888888888888888888888888'
      INTO @DATA(distinct_keys).
    cl_abap_unit_assert=>assert_equals( act = distinct_keys exp = 3 msg = 'server-side UUIDs are unique' ).
  ENDMETHOD.

  METHOD release_order_rejects_zero.
    DATA materials TYPE STANDARD TABLE OF zsce_material WITH EMPTY KEY.
    materials = VALUE #( ( material_uuid = 'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC'
                           matnr = 'Marine' bukrs = '1000' category = 'UNIT' mineral_cost = 50 ) ).
    sql->insert_test_data( materials ).

    MODIFY ENTITIES OF zi_scegame
      ENTITY game
        CREATE FIELDS ( gameuuid replayhash )
        WITH VALUE #( ( %cid = 'g1' gameuuid = 'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF' replayhash = 'ZER' ) )
        CREATE BY \_Division FIELDS ( divisionuuid companycode divisioncode )
        WITH VALUE #( ( %cid_ref = 'g1'
                        %target  = VALUE #( ( %cid = 'd1' divisionuuid = 'EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE'
                                              companycode = '1000' divisioncode = 'P1' ) ) ) )
      MAPPED DATA(seed_mapped) FAILED DATA(seed_failed) REPORTED DATA(seed_reported).

    MODIFY ENTITIES OF zi_scegame
      ENTITY division
        EXECUTE releaseorder
          FROM VALUE #( ( divisionuuid = 'EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE'
                          %param = VALUE #( material = 'Marine' quantity = 0 ) ) )
      FAILED DATA(failed) REPORTED DATA(reported).

    cl_abap_unit_assert=>assert_not_initial( act = failed-division msg = 'quantity 0 must fail' ).
    ROLLBACK ENTITIES.
    SELECT COUNT( * ) FROM zsce_prodord INTO @DATA(orders).
    cl_abap_unit_assert=>assert_equals( act = orders exp = 0 msg = 'nothing created' ).
  ENDMETHOD.

  METHOD release_order_defaults.
    MODIFY ENTITIES OF zi_scegame
      ENTITY game
        CREATE FIELDS ( gameuuid replayhash )
        WITH VALUE #( ( %cid = 'g1' gameuuid = 'DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD' replayhash = 'DEFAULTS' ) )
        CREATE BY \_Division FIELDS ( divisionuuid companycode divisioncode )
        WITH VALUE #( ( %cid_ref = 'g1'
                        %target  = VALUE #( ( %cid = 'd1' divisionuuid = 'EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE'
                                              companycode = '1000' divisioncode = 'P1' ) ) ) )
      MAPPED DATA(mapped) FAILED DATA(failed) REPORTED DATA(reported).

    READ ENTITIES OF zi_scegame
      ENTITY division
        EXECUTE getdefaultsforreleaseorder
          FROM VALUE #( ( divisionuuid = 'EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE' ) )
        RESULT DATA(defaults).

    cl_abap_unit_assert=>assert_equals( act = lines( defaults ) exp = 1 msg = 'one default row per key' ).
    cl_abap_unit_assert=>assert_equals( act = defaults[ 1 ]-%param-quantity exp = 1 msg = 'quantity defaults to 1' ).
    cl_abap_unit_assert=>assert_equals( act = defaults[ 1 ]-%param-withprerequisites exp = abap_true
                                        msg = 'the prerequisites checkbox starts ticked' ).
    cl_abap_unit_assert=>assert_equals( act = defaults[ 1 ]-%param-divisionuuid
                                        exp = CONV sysuuid_x16( 'EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE' )
                                        msg = 'the bound division is passed to the value help' ).
  ENDMETHOD.

  METHOD buildable_reason_texts.
    DATA row TYPE zi_scebuildablematerial.
    row = VALUE #( material = 'Marine' producedby = 'Barracks' produceronhand = 0 mineralcost = 50 mineralsonhand = 500 ).
    cl_abap_unit_assert=>assert_equals( act = lcl_buildable=>why( row ) exp = `no Barracks on hand yet` ).
    row = VALUE #( material = 'Marauder' producedby = 'Barracks' produceronhand = 1
                   prerequisite = 'BarracksTechLab' prerequisiteonhand = 0 mineralcost = 100 mineralsonhand = 500 ).
    cl_abap_unit_assert=>assert_equals( act = lcl_buildable=>why( row ) exp = `requires BarracksTechLab` ).
    row = VALUE #( material = 'Barracks' producedby = 'SCV' produceronhand = 8 mineralcost = 150 mineralsonhand = 90 ).
    cl_abap_unit_assert=>assert_equals( act = lcl_buildable=>why( row ) exp = `needs 150 minerals, has 90` ).
    row = VALUE #( material = 'Marauder' producedby = 'Barracks' produceronhand = 1 prerequisite = 'BarracksTechLab'
                   prerequisiteonhand = 1 mineralcost = 100 mineralsonhand = 500 gascost = 25 gasonhand = 0 ).
    cl_abap_unit_assert=>assert_equals( act = lcl_buildable=>why( row ) exp = `needs 25 gas, has 0` ).
    row-buildable = 'X'.
    cl_abap_unit_assert=>assert_initial( act = lcl_buildable=>why( row ) ).
  ENDMETHOD.
ENDCLASS.

CLASS ltc_requirements DEFINITION FINAL FOR TESTING
  DURATION SHORT RISK LEVEL HARMLESS.
  PRIVATE SECTION.
    CONSTANTS division TYPE sysuuid_x16 VALUE 'ABABABABABABABABABABABABABABABAB'.
    CLASS-DATA sql TYPE REF TO if_osql_test_environment.
    CLASS-METHODS class_setup.
    CLASS-METHODS class_teardown.
    METHODS setup.
    METHODS chain_dependencies_first FOR TESTING.
    METHODS release_adds_prerequisites FOR TESTING RAISING cx_static_check.
ENDCLASS.

CLASS ltc_requirements IMPLEMENTATION.
  METHOD class_setup.
    sql = cl_osql_test_environment=>create(
            VALUE #( ( 'ZSCE_GAME' ) ( 'ZSCE_DIVISION' ) ( 'ZSCE_PLANT' )
                     ( 'ZSCE_PRODORD' ) ( 'ZSCE_EVENT' ) ( 'ZSCE_MATERIAL' ) ) ).
  ENDMETHOD.

  METHOD class_teardown.
    sql->destroy( ).
  ENDMETHOD.

  METHOD setup.
    sql->clear_doubles( ).
    ROLLBACK ENTITIES.
  ENDMETHOD.

  METHOD chain_dependencies_first.
    DATA(tech) = VALUE lcl_requirements=>tt_tech(
      ( material = 'Barracks'        producedby = 'SCV'           prerequisite = 'SupplyDepot' )
      ( material = 'BarracksTechLab' producedby = 'Barracks' )
      ( material = 'CommandCenter'   producedby = 'SCV' )
      ( material = 'Marauder'        producedby = 'Barracks'      prerequisite = 'BarracksTechLab' )
      ( material = 'Marine'          producedby = 'Barracks' )
      ( material = 'SCV'             producedby = 'CommandCenter' )
      ( material = 'SupplyDepot'     producedby = 'SCV' ) ).
    cl_abap_unit_assert=>assert_equals(
      act = lcl_requirements=>missing( material = 'Marauder' tech = tech covered = VALUE #( ( 'SCV' ) ( 'CommandCenter' ) ) )
      exp = VALUE lcl_requirements=>tt_materials( ( 'SupplyDepot' ) ( 'Barracks' ) ( 'BarracksTechLab' ) )
      msg = 'dependencies first, the Barracks only once' ).
    cl_abap_unit_assert=>assert_equals(
      act = lcl_requirements=>missing( material = 'Marauder' tech = tech
                                       covered = VALUE #( ( 'SCV' ) ( 'CommandCenter' ) ( 'SupplyDepot' ) ( 'Barracks' ) ) )
      exp = VALUE lcl_requirements=>tt_materials( ( 'BarracksTechLab' ) )
      msg = 'covered producers are not ordered again' ).
    cl_abap_unit_assert=>assert_initial(
      act = lcl_requirements=>missing( material = 'Marine' tech = tech covered = VALUE #( ( 'Barracks' ) ) ) ).
    cl_abap_unit_assert=>assert_equals(
      act = lcl_requirements=>missing( material = 'SCV' tech = tech covered = VALUE #( ) )
      exp = VALUE lcl_requirements=>tt_materials( ( 'CommandCenter' ) )
      msg = 'the SCV <-> CommandCenter loop terminates' ).
    cl_abap_unit_assert=>assert_initial(
      act = lcl_requirements=>missing( material = 'Mystery' tech = tech covered = VALUE #( ) ) ).
  ENDMETHOD.

  METHOD release_adds_prerequisites.
    TYPES: BEGIN OF ty_count,
             matnr TYPE zsce_prodord-matnr,
             n     TYPE i,
           END OF ty_count,
           tt_count TYPE STANDARD TABLE OF ty_count WITH EMPTY KEY.
    DATA materials TYPE STANDARD TABLE OF zsce_material WITH EMPTY KEY.
    DATA orders TYPE STANDARD TABLE OF zsce_prodord WITH EMPTY KEY.
    DATA released TYPE tt_count.
    materials = VALUE #( bukrs = '1000'
      ( material_uuid = 'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCC01' matnr = 'Marine' category = 'UNIT' mineral_cost = 50
        produced_by = 'Barracks' )
      ( material_uuid = 'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCC02' matnr = 'Barracks' category = 'STRUCTURE' mineral_cost = 150
        produced_by = 'SCV' prerequisite = 'SupplyDepot' )
      ( material_uuid = 'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCC03' matnr = 'SupplyDepot' category = 'STRUCTURE' mineral_cost = 100
        produced_by = 'SCV' )
      ( material_uuid = 'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCC04' matnr = 'SCV' category = 'UNIT' mineral_cost = 50
        produced_by = 'CommandCenter' )
      ( material_uuid = 'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCC05' matnr = 'CommandCenter' category = 'STRUCTURE' mineral_cost = 400
        produced_by = 'SCV' ) ).
    sql->insert_test_data( materials ).
    " SCV and Command Center are already on order: that covers them like stock on hand
    orders = VALUE #( division_uuid = division quantity = 1
      ( order_uuid = 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBB01' matnr = 'CommandCenter' order_status = 'STARTED' )
      ( order_uuid = 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBB02' matnr = 'SCV' order_status = 'RELEASED' ) ).
    sql->insert_test_data( orders ).

    MODIFY ENTITIES OF zi_scegame
      ENTITY game
        CREATE FIELDS ( gameuuid replayhash )
        WITH VALUE #( ( %cid = 'g1' gameuuid = 'ACACACACACACACACACACACACACACACAC' replayhash = 'PREREQ' ) )
        CREATE BY \_Division FIELDS ( divisionuuid companycode divisioncode )
        WITH VALUE #( ( %cid_ref = 'g1'
                        %target  = VALUE #( ( %cid = 'd1' divisionuuid = division companycode = '1000' divisioncode = 'P1' ) ) ) )
      MAPPED DATA(seed_mapped) FAILED DATA(seed_failed) REPORTED DATA(seed_reported).

    MODIFY ENTITIES OF zi_scegame
      ENTITY division
        EXECUTE releaseorder
          FROM VALUE #( ( divisionuuid = division
                          %param = VALUE #( material = 'Marine' quantity = 5 withprerequisites = abap_true ) ) )
      FAILED DATA(failed) REPORTED DATA(reported).
    COMMIT ENTITIES RESPONSE OF zi_scegame
      FAILED DATA(commit_failed) REPORTED DATA(commit_reported).

    cl_abap_unit_assert=>assert_initial( act = failed-division msg = 'valid release must not fail' ).
    cl_abap_unit_assert=>assert_initial( act = commit_failed msg = 'release must save' ).
    SELECT matnr, COUNT( * ) AS n FROM zsce_prodord
      WHERE division_uuid = @division AND order_status = 'RELEASED'
      GROUP BY matnr
      ORDER BY matnr
      INTO CORRESPONDING FIELDS OF TABLE @released.
    cl_abap_unit_assert=>assert_equals(
      act = released
      exp = VALUE tt_count( ( matnr = 'Barracks' n = 1 ) ( matnr = 'Marine' n = 5 )
                            ( matnr = 'SCV' n = 1 ) ( matnr = 'SupplyDepot' n = 1 ) )
      msg = 'one Supply Depot and one Barracks with the 5 Marines; SCV and Command Center were covered' ).
  ENDMETHOD.
ENDCLASS.

CLASS ltc_cancel DEFINITION FINAL FOR TESTING
  DURATION SHORT RISK LEVEL HARMLESS.
  PRIVATE SECTION.
    CONSTANTS game     TYPE sysuuid_x16 VALUE 'CA000000000000000000000000000001'.
    CONSTANTS division TYPE sysuuid_x16 VALUE 'CA000000000000000000000000000002'.
    CONSTANTS waiting  TYPE sysuuid_x16 VALUE 'CA000000000000000000000000000003'.
    CONSTANTS started  TYPE sysuuid_x16 VALUE 'CA000000000000000000000000000004'.
    CONSTANTS confirmed  TYPE sysuuid_x16 VALUE 'CA000000000000000000000000000005'.
    CONSTANTS cancelling TYPE sysuuid_x16 VALUE 'CA000000000000000000000000000006'.
    CLASS-DATA sql TYPE REF TO if_osql_test_environment.
    CLASS-METHODS class_setup.
    CLASS-METHODS class_teardown.
    METHODS setup.
    METHODS cancel_waiting_order FOR TESTING RAISING cx_static_check.
    METHODS started_order_requests_cancel FOR TESTING RAISING cx_static_check.
    METHODS finished_orders_are_refused FOR TESTING RAISING cx_static_check.
    METHODS cancel_offered_until_built FOR TESTING RAISING cx_static_check.
    METHODS order_of IMPORTING uuid TYPE sysuuid_x16 RETURNING VALUE(row) TYPE zsce_prodord.
ENDCLASS.

CLASS ltc_cancel IMPLEMENTATION.
  METHOD class_setup.
    sql = cl_osql_test_environment=>create(
            VALUE #( ( 'ZSCE_GAME' ) ( 'ZSCE_DIVISION' ) ( 'ZSCE_PLANT' )
                     ( 'ZSCE_PRODORD' ) ( 'ZSCE_EVENT' ) ( 'ZSCE_MATERIAL' ) ) ).
  ENDMETHOD.

  METHOD class_teardown.
    sql->destroy( ).
  ENDMETHOD.

  METHOD setup.
    " one waiting order and one the bot has already queued in the game; created in the test's LUW,
    " because READ ENTITIES and actions do not see rows committed into the OSQL doubles
    sql->clear_doubles( ).
    ROLLBACK ENTITIES.
    MODIFY ENTITIES OF zi_scegame
      ENTITY game
        CREATE FIELDS ( gameuuid replayhash )
        WITH VALUE #( ( %cid = 'g1' gameuuid = game replayhash = 'CANCEL' ) )
        CREATE BY \_Division FIELDS ( divisionuuid companycode divisioncode )
        WITH VALUE #( ( %cid_ref = 'g1'
                        %target  = VALUE #( ( %cid = 'd1' divisionuuid = division companycode = '1000' divisioncode = 'P1' ) ) ) )
      ENTITY division
        CREATE BY \_ProdOrder FIELDS ( orderuuid material quantity orderstatus )
        WITH VALUE #( ( %cid_ref = 'd1'
                        %target  = VALUE #( ( %cid = 'o1' orderuuid = waiting material = 'Marine' quantity = 1
                                              orderstatus = 'RELEASED' )
                                            ( %cid = 'o2' orderuuid = started material = 'Marine' quantity = 1
                                              orderstatus = 'STARTED' )
                                            ( %cid = 'o3' orderuuid = confirmed material = 'Marine' quantity = 1
                                              orderstatus = 'CONFIRMED' )
                                            ( %cid = 'o4' orderuuid = cancelling material = 'Marine' quantity = 1
                                              orderstatus = 'CANCELLING' ) ) ) )
      MAPPED DATA(mapped) FAILED DATA(failed) REPORTED DATA(reported).
    cl_abap_unit_assert=>assert_initial( act = failed msg = 'seed must be accepted' ).
  ENDMETHOD.

  METHOD order_of.
    SELECT SINGLE * FROM zsce_prodord WHERE order_uuid = @uuid INTO @row.
  ENDMETHOD.

  METHOD cancel_waiting_order.
    MODIFY ENTITIES OF zi_scegame
      ENTITY prodorder
        EXECUTE cancelorder FROM VALUE #( ( orderuuid = waiting ) )
        RESULT DATA(result)
      FAILED DATA(failed) REPORTED DATA(reported).
    COMMIT ENTITIES RESPONSE OF zi_scegame
      FAILED DATA(commit_failed) REPORTED DATA(commit_reported).

    cl_abap_unit_assert=>assert_initial( act = failed-prodorder msg = 'a RELEASED order can be cancelled' ).
    cl_abap_unit_assert=>assert_initial( act = commit_failed msg = 'the cancel must save' ).
    cl_abap_unit_assert=>assert_equals( act = order_of( waiting )-order_status exp = 'CANCELLED' ).
    cl_abap_unit_assert=>assert_equals( act = order_of( waiting )-status_text exp = 'cancelled in SAP' ).
    READ TABLE result INDEX 1 INTO DATA(returned).
    cl_abap_unit_assert=>assert_equals( act = returned-%param-orderstatus exp = 'CANCELLED'
                                        msg = 'the action returns the cancelled order' ).
  ENDMETHOD.

  METHOD started_order_requests_cancel.
    MODIFY ENTITIES OF zi_scegame
      ENTITY prodorder
        EXECUTE cancelorder FROM VALUE #( ( orderuuid = started ) )
      FAILED DATA(failed) REPORTED DATA(reported).
    COMMIT ENTITIES RESPONSE OF zi_scegame
      FAILED DATA(commit_failed) REPORTED DATA(commit_reported).

    cl_abap_unit_assert=>assert_initial( act = failed-prodorder msg = 'the bot cancels a STARTED order in the game' ).
    cl_abap_unit_assert=>assert_equals( act = order_of( started )-order_status exp = 'CANCELLING' ).
    cl_abap_unit_assert=>assert_equals( act = order_of( started )-status_text exp = 'cancel requested' ).
  ENDMETHOD.

  METHOD finished_orders_are_refused.
    MODIFY ENTITIES OF zi_scegame
      ENTITY prodorder
        EXECUTE cancelorder FROM VALUE #( ( orderuuid = confirmed ) ( orderuuid = cancelling ) )
      FAILED DATA(failed) REPORTED DATA(reported).
    COMMIT ENTITIES RESPONSE OF zi_scegame
      FAILED DATA(commit_failed) REPORTED DATA(commit_reported).

    cl_abap_unit_assert=>assert_equals( act = lines( failed-prodorder ) exp = 2 msg = 'built, or already being cancelled' ).
    cl_abap_unit_assert=>assert_equals( act = order_of( confirmed )-order_status exp = 'CONFIRMED' ).
    cl_abap_unit_assert=>assert_equals( act = order_of( cancelling )-order_status exp = 'CANCELLING' ).
  ENDMETHOD.

  METHOD cancel_offered_until_built.
    GET PERMISSIONS ONLY INSTANCE FEATURES ENTITY zi_sceprodorder
      FROM VALUE #( ( orderuuid = waiting ) ( orderuuid = started ) ( orderuuid = confirmed ) ( orderuuid = cancelling ) )
      REQUEST VALUE #( %action-cancelorder = if_abap_behv=>mk-on )
      RESULT DATA(permissions)
      FAILED DATA(failed)
      REPORTED DATA(reported).

    " GET PERMISSIONS answers only restricted instances: no row means the action is enabled
    cl_abap_unit_assert=>assert_equals( act = lines( permissions-instances ) exp = 2
                                        msg = 'only CONFIRMED and CANCELLING are restricted' ).
    cl_abap_unit_assert=>assert_false( act = xsdbool( line_exists( permissions-instances[ orderuuid = waiting ] ) ) ).
    cl_abap_unit_assert=>assert_false( act = xsdbool( line_exists( permissions-instances[ orderuuid = started ] ) ) ).
    LOOP AT permissions-instances INTO DATA(restricted).
      cl_abap_unit_assert=>assert_equals( act = restricted-%action-cancelorder exp = if_abap_behv=>fc-o-disabled ).
    ENDLOOP.
  ENDMETHOD.
ENDCLASS.

CLASS ltc_mrp DEFINITION FINAL FOR TESTING
  DURATION SHORT RISK LEVEL HARMLESS.
  PRIVATE SECTION.
    CLASS-METHODS terran RETURNING VALUE(result) TYPE lcl_mrp=>tt_master.
    CLASS-METHODS start_stock RETURNING VALUE(result) TYPE lcl_mrp=>tt_available.
    METHODS shortage_in_lots_of_five FOR TESTING.
    METHODS pirs_add_up_in_due_order FOR TESTING.
    METHODS marauders_pull_the_tech_chain FOR TESTING.
    METHODS one_barracks_for_two_targets FOR TESTING.
    METHODS target_is_not_planned_twice FOR TESTING.
    METHODS structures_one_per_order FOR TESTING.
    METHODS exceptions_against_the_clock FOR TESTING.
    METHODS covered_target_plans_nothing FOR TESTING.
    CONSTANTS f1 TYPE sysuuid_x16 VALUE 'F1000000000000000000000000000001'.
    CONSTANTS f2 TYPE sysuuid_x16 VALUE 'F1000000000000000000000000000002'.
    METHODS late_target_is_moved FOR TESTING.
    METHODS firmed_late_is_flagged FOR TESTING.
    METHODS movable_before_firmed FOR TESTING.
    METHODS worker_town_hall_cycle FOR TESTING.
    METHODS cycle_of_three FOR TESTING.
    METHODS own_producer_is_ignored FOR TESTING.
    METHODS firmed_inside_a_cycle FOR TESTING.
    METHODS firmed_unknown_material FOR TESTING.
    METHODS firmed_lot_covers_target FOR TESTING.
    METHODS firmed_lots_in_key_order FOR TESTING.
    METHODS firmed_rest_is_carried FOR TESTING.
    METHODS past_beats_reschedule FOR TESTING.
    CLASS-METHODS terran_supply RETURNING VALUE(result) TYPE lcl_mrp=>tt_master.
    CLASS-METHODS no_source RETURNING VALUE(result) TYPE lcl_mrp=>tt_master.
    CLASS-METHODS fresh_game RETURNING VALUE(result) TYPE lcl_mrp=>tt_available.
    METHODS supply_example FOR TESTING.
    METHODS free_supply_plans_no_depot FOR TESTING.
    METHODS late_receipt_does_not_cover FOR TESTING.
    METHODS open_orders_beyond_capacity FOR TESTING.
    METHODS cap_of_200 FOR TESTING.
    METHODS no_source_stays_short FOR TESTING.
    METHODS source_per_company FOR TESTING.
    METHODS nobody_to_build_it FOR TESTING.
    METHODS planned_worker_builds_depot FOR TESTING.
    METHODS blocked_worker_gives_nothing FOR TESTING.
    METHODS short_in_the_precedence FOR TESTING.
ENDCLASS.

CLASS ltc_mrp IMPLEMENTATION.
  METHOD terran.
    result = VALUE #(
      ( material = 'Barracks'        producedby = 'SCV'           prerequisite = 'SupplyDepot'     category = 'STRUCTURE' buildseconds = 46 )
      ( material = 'BarracksTechLab' producedby = 'Barracks'                                       category = 'STRUCTURE' buildseconds = 18 )
      ( material = 'CommandCenter'   producedby = 'SCV'                                            category = 'STRUCTURE' buildseconds = 71 )
      ( material = 'Marauder'        producedby = 'Barracks'      prerequisite = 'BarracksTechLab' category = 'UNIT'      buildseconds = 21 )
      ( material = 'Marine'          producedby = 'Barracks'                                       category = 'UNIT'      buildseconds = 18 )
      ( material = 'SCV'             producedby = 'CommandCenter'                                  category = 'UNIT'      buildseconds = 12 )
      ( material = 'SupplyDepot'     producedby = 'SCV'                                            category = 'STRUCTURE' buildseconds = 21 ) ).
  ENDMETHOD.

  METHOD start_stock.
    result = VALUE #( ( material = 'CommandCenter' quantity = 1 ) ( material = 'SCV' quantity = 8 ) ).
  ENDMETHOD.

  METHOD shortage_in_lots_of_five.
    " 20 Marines by 300 s against 3 on hand + 2 on order: 15 short, 3 lots of 5 x 18 s
    cl_abap_unit_assert=>assert_equals(
      act = lcl_mrp=>plan( clock  = 0
                           pirs   = VALUE #( ( material = 'Marine' quantity = 20 due = 300 ) )
                           available = VALUE #( BASE start_stock( ) ( material = 'Barracks' quantity = 1 )
                                             ( material = 'Marine' quantity = 3 ) ( material = 'Marine' quantity = 2 ) )
                           master = terran( ) )
      exp = VALUE lcl_mrp=>tt_planned( ( material = 'Marine' quantity = 5 start = 210 finish = 300 )
                                       ( material = 'Marine' quantity = 5 start = 210 finish = 300 )
                                       ( material = 'Marine' quantity = 5 start = 210 finish = 300 ) ) ).
  ENDMETHOD.

  METHOD pirs_add_up_in_due_order.
    " 10 by 300 s and 10 by 480 s, 12 available: the earlier target takes 10, the later one is 8 short
    cl_abap_unit_assert=>assert_equals(
      act = lcl_mrp=>plan( clock  = 0
                           pirs   = VALUE #( ( material = 'Marine' quantity = 10 due = 480 )
                                             ( material = 'Marine' quantity = 10 due = 300 ) )
                           available = VALUE #( BASE start_stock( ) ( material = 'Barracks' quantity = 1 )
                                             ( material = 'Marine' quantity = 12 ) )
                           master = terran( ) )
      exp = VALUE lcl_mrp=>tt_planned( ( material = 'Marine' quantity = 5 start = 390 finish = 480 )
                                       ( material = 'Marine' quantity = 3 start = 426 finish = 480 ) ) ).
  ENDMETHOD.

  METHOD marauders_pull_the_tech_chain.
    " the spec's example: 10 Marauders by 300 s in a fresh game
    cl_abap_unit_assert=>assert_equals(
      act = lcl_mrp=>plan( clock  = 0
                           pirs   = VALUE #( ( material = 'Marauder' quantity = 10 due = 300 ) )
                           available = start_stock( )
                           master = terran( ) )
      exp = VALUE lcl_mrp=>tt_planned(
              ( material = 'Marauder'        quantity = 5 start = 195 finish = 300 )
              ( material = 'Marauder'        quantity = 5 start = 195 finish = 300 )
              ( material = 'BarracksTechLab' quantity = 1 start = 177 finish = 195 plannedfor = 'Marauder' )
              ( material = 'Barracks'        quantity = 1 start = 131 finish = 177 plannedfor = 'BarracksTechLab' )
              ( material = 'SupplyDepot'     quantity = 1 start = 110 finish = 131 plannedfor = 'Barracks' ) ) ).
  ENDMETHOD.

  METHOD one_barracks_for_two_targets.
    " Marines start at 210, Marauders at 295: one Barracks, due when the Marines start
    cl_abap_unit_assert=>assert_equals(
      act = lcl_mrp=>plan( clock  = 0
                           pirs   = VALUE #( ( material = 'Marine'   quantity = 5 due = 300 )
                                             ( material = 'Marauder' quantity = 5 due = 400 ) )
                           available = start_stock( )
                           master = terran( ) )
      exp = VALUE lcl_mrp=>tt_planned(
              ( material = 'Marine'          quantity = 5 start = 210 finish = 300 )
              ( material = 'Marauder'        quantity = 5 start = 295 finish = 400 )
              ( material = 'BarracksTechLab' quantity = 1 start = 277 finish = 295 plannedfor = 'Marauder' )
              ( material = 'Barracks'        quantity = 1 start = 164 finish = 210 plannedfor = 'Marine' )
              ( material = 'SupplyDepot'     quantity = 1 start = 143 finish = 164 plannedfor = 'Barracks' ) ) ).
  ENDMETHOD.

  METHOD target_is_not_planned_twice.
    " the planned Barracks target covers the Marines' producer
    cl_abap_unit_assert=>assert_equals(
      act = lcl_mrp=>plan( clock  = 0
                           pirs   = VALUE #( ( material = 'Barracks' quantity = 1 due = 100 )
                                             ( material = 'Marine'   quantity = 5 due = 300 ) )
                           available = VALUE #( BASE start_stock( ) ( material = 'SupplyDepot' quantity = 1 ) )
                           master = terran( ) )
      exp = VALUE lcl_mrp=>tt_planned( ( material = 'Barracks' quantity = 1 start = 54  finish = 100 )
                                       ( material = 'Marine'   quantity = 5 start = 210 finish = 300 ) ) ).
  ENDMETHOD.

  METHOD structures_one_per_order.
    cl_abap_unit_assert=>assert_equals(
      act = lcl_mrp=>plan( clock  = 0
                           pirs   = VALUE #( ( material = 'Barracks' quantity = 3 due = 200 ) )
                           available = VALUE #( BASE start_stock( ) ( material = 'SupplyDepot' quantity = 1 ) )
                           master = terran( ) )
      exp = VALUE lcl_mrp=>tt_planned( ( material = 'Barracks' quantity = 1 start = 154 finish = 200 )
                                       ( material = 'Barracks' quantity = 1 start = 154 finish = 200 )
                                       ( material = 'Barracks' quantity = 1 start = 154 finish = 200 ) ) ).
  ENDMETHOD.

  METHOD exceptions_against_the_clock.
    DATA(pirs) = VALUE lcl_mrp=>tt_pirs( ( material = 'Marine' quantity = 5 due = 300 ) ).
    DATA(supply) = VALUE lcl_mrp=>tt_available( BASE start_stock( ) ( material = 'Barracks' quantity = 1 ) ).
    cl_abap_unit_assert=>assert_equals(
      act = lcl_mrp=>plan( clock = 250 pirs = pirs available = supply master = terran( ) )
      exp = VALUE lcl_mrp=>tt_planned( ( material = 'Marine' quantity = 5 start = 210 finish = 300
                                         exception = 'start in the past' ) ) ).
    cl_abap_unit_assert=>assert_equals(
      act = lcl_mrp=>plan( clock = 350 pirs = pirs available = supply master = terran( ) )
      exp = VALUE lcl_mrp=>tt_planned( ( material = 'Marine' quantity = 5 start = 210 finish = 300
                                         exception = 'finish in the past' ) ) ).
  ENDMETHOD.

  METHOD covered_target_plans_nothing.
    " enough Marauders on hand: no lot, and no TechLab or Barracks for a lot that does not exist
    cl_abap_unit_assert=>assert_initial(
      lcl_mrp=>plan( clock  = 0
                     pirs   = VALUE #( ( material = 'Marauder' quantity = 5 due = 300 ) )
                     available = VALUE #( BASE start_stock( ) ( material = 'Marauder' quantity = 5 ) )
                     master = terran( ) ) ).
  ENDMETHOD.

  METHOD late_target_is_moved.
    " spec example 2: the Marines start at 360, so the Barracks planned for 500 moves to 314-360, its depot follows
    cl_abap_unit_assert=>assert_equals(
      act = lcl_mrp=>plan( clock     = 0
                           pirs      = VALUE #( ( material = 'Barracks' quantity = 1 due = 500 )
                                                ( material = 'Marine'   quantity = 5 due = 450 ) )
                           available = start_stock( )
                           master    = terran( ) )
      exp = VALUE lcl_mrp=>tt_planned(
              ( material = 'Marine'      quantity = 5 start = 360 finish = 450 )
              ( material = 'Barracks'    quantity = 1 start = 314 finish = 360 )
              ( material = 'SupplyDepot' quantity = 1 start = 293 finish = 314 plannedfor = 'Barracks' ) ) ).
  ENDMETHOD.

  METHOD firmed_late_is_flagged.
    " a firmed Barracks finishing at 500 is all there is: flagged for the Marines' start, not moved
    lcl_mrp=>plan( EXPORTING clock     = 0
                             pirs      = VALUE #( ( material = 'Marine' quantity = 5 due = 450 ) )
                             available = VALUE #( BASE start_stock( ) ( material = 'SupplyDepot' quantity = 1 ) )
                             firmed    = VALUE #( ( id = f1 material = 'Barracks' quantity = 1 start = 454 finish = 500 ) )
                             master    = terran( )
                   IMPORTING firmed_texts = DATA(texts)
                   RECEIVING result       = DATA(plan) ).
    cl_abap_unit_assert=>assert_equals(
      act = plan
      exp = VALUE lcl_mrp=>tt_planned( ( material = 'Marine' quantity = 5 start = 360 finish = 450 ) ) ).
    cl_abap_unit_assert=>assert_equals(
      act = texts
      exp = VALUE lcl_mrp=>tt_firmed_texts( ( id = f1 exception = 'reschedule in to 360 s' ) ) ).
  ENDMETHOD.

  METHOD movable_before_firmed.
    " two Barracks due 500, one of them firmed: the unfirmed one moves for the Marines, the firmed one is left alone
    lcl_mrp=>plan( EXPORTING clock     = 0
                             pirs      = VALUE #( ( material = 'Barracks' quantity = 2 due = 500 )
                                                  ( material = 'Marine'   quantity = 5 due = 450 ) )
                             available = VALUE #( BASE start_stock( ) ( material = 'SupplyDepot' quantity = 1 ) )
                             firmed    = VALUE #( ( id = f1 material = 'Barracks' quantity = 1 start = 454 finish = 500 ) )
                             master    = terran( )
                   IMPORTING firmed_texts = DATA(texts)
                   RECEIVING result       = DATA(plan) ).
    cl_abap_unit_assert=>assert_equals(
      act = plan
      exp = VALUE lcl_mrp=>tt_planned( ( material = 'Marine'   quantity = 5 start = 360 finish = 450 )
                                       ( material = 'Barracks' quantity = 1 start = 314 finish = 360 ) ) ).
    cl_abap_unit_assert=>assert_equals(
      act = texts exp = VALUE lcl_mrp=>tt_firmed_texts( ( id = f1 ) ) msg = 'the firmed Barracks gets no text' ).
  ENDMETHOD.

  METHOD worker_town_hall_cycle.
    " a division with nothing: the SCV needs a Command Center, which needs an SCV; the run must end
    cl_abap_unit_assert=>assert_equals(
      act = lcl_mrp=>plan( clock     = 0
                           pirs      = VALUE #( ( material = 'SCV' quantity = 1 due = 100 ) )
                           available = VALUE #( )
                           master    = terran( ) )
      exp = VALUE lcl_mrp=>tt_planned(
              ( material = 'SCV'           quantity = 1 start = 88 finish = 100 )
              ( material = 'CommandCenter' quantity = 1 start = 17 finish = 88 plannedfor = 'SCV' ) ) ).
  ENDMETHOD.

  METHOD cycle_of_three.
    " A is made by B, B by C, C by A: C's need for A returns through B and is cut
    cl_abap_unit_assert=>assert_equals(
      act = lcl_mrp=>plan( clock     = 0
                           pirs      = VALUE #( ( material = 'A' quantity = 1 due = 100 ) )
                           available = VALUE #( )
                           master    = VALUE #( ( material = 'A' producedby = 'B' category = 'STRUCTURE' buildseconds = 10 )
                                                ( material = 'B' producedby = 'C' category = 'STRUCTURE' buildseconds = 20 )
                                                ( material = 'C' producedby = 'A' category = 'STRUCTURE' buildseconds = 30 ) ) )
      exp = VALUE lcl_mrp=>tt_planned( ( material = 'A' quantity = 1 start = 90 finish = 100 )
                                       ( material = 'B' quantity = 1 start = 70 finish = 90 plannedfor = 'A' )
                                       ( material = 'C' quantity = 1 start = 40 finish = 70 plannedfor = 'B' ) ) ).
  ENDMETHOD.

  METHOD own_producer_is_ignored.
    " a material that names itself as its producer: the order cannot cover its own need and keeps its dates
    cl_abap_unit_assert=>assert_equals(
      act = lcl_mrp=>plan( clock     = 0
                           pirs      = VALUE #( ( material = 'A' quantity = 1 due = 100 ) )
                           available = VALUE #( )
                           master    = VALUE #( ( material = 'A' producedby = 'A' category = 'STRUCTURE' buildseconds = 10 ) ) )
      exp = VALUE lcl_mrp=>tt_planned( ( material = 'A' quantity = 1 start = 90 finish = 100 ) ) ).
  ENDMETHOD.

  METHOD firmed_inside_a_cycle.
    " no target, a firmed SCV: its Command Center is planned, the return need is cut, the SCV is not flagged
    lcl_mrp=>plan( EXPORTING clock     = 0
                             pirs      = VALUE #( )
                             available = VALUE #( )
                             firmed    = VALUE #( ( id = f1 material = 'SCV' quantity = 1 start = 88 finish = 100 ) )
                             master    = terran( )
                   IMPORTING firmed_texts = DATA(texts)
                   RECEIVING result       = DATA(plan) ).
    cl_abap_unit_assert=>assert_equals(
      act = plan
      exp = VALUE lcl_mrp=>tt_planned(
              ( material = 'CommandCenter' quantity = 1 start = 17 finish = 88 plannedfor = 'SCV' ) ) ).
    cl_abap_unit_assert=>assert_equals( act = texts exp = VALUE lcl_mrp=>tt_firmed_texts( ( id = f1 ) ) ).
  ENDMETHOD.

  METHOD firmed_unknown_material.
    " a firmed order of a material the company's master does not know: kept, nothing planned for it
    lcl_mrp=>plan( EXPORTING clock     = 0
                             pirs      = VALUE #( )
                             available = start_stock( )
                             firmed    = VALUE #( ( id = f1 material = 'Zergling' quantity = 4 start = 10 finish = 50 ) )
                             master    = terran( )
                   IMPORTING firmed_texts = DATA(texts)
                   RECEIVING result       = DATA(plan) ).
    cl_abap_unit_assert=>assert_initial( plan ).
    cl_abap_unit_assert=>assert_equals( act = texts exp = VALUE lcl_mrp=>tt_firmed_texts( ( id = f1 ) ) ).
  ENDMETHOD.

  METHOD firmed_lot_covers_target.
    " spec example 3: the firmed lot (finish 540) is taken for a target due 420: no new lot, flagged
    DATA(target) = VALUE lcl_mrp=>tt_pirs( ( material = 'Marauder' quantity = 5 due = 420 ) ).
    lcl_mrp=>plan( EXPORTING clock     = 0
                             pirs      = target
                             available = start_stock( )
                             firmed    = VALUE #( ( id = f1 material = 'Marauder' quantity = 5 start = 435 finish = 540 ) )
                             master    = terran( )
                   IMPORTING firmed_texts = DATA(texts)
                   RECEIVING result       = DATA(plan) ).
    cl_abap_unit_assert=>assert_equals(
      act = plan
      exp = VALUE lcl_mrp=>tt_planned(
              ( material = 'BarracksTechLab' quantity = 1 start = 417 finish = 435 plannedfor = 'Marauder' )
              ( material = 'Barracks'        quantity = 1 start = 371 finish = 417 plannedfor = 'BarracksTechLab' )
              ( material = 'SupplyDepot'     quantity = 1 start = 350 finish = 371 plannedfor = 'Barracks' ) ) ).
    cl_abap_unit_assert=>assert_equals(
      act = texts
      exp = VALUE lcl_mrp=>tt_firmed_texts( ( id = f1 exception = 'reschedule in to 420 s' ) ) ).
    " unfirmed, the run replaces it with a lot that meets the target
    cl_abap_unit_assert=>assert_equals(
      act = lcl_mrp=>plan( clock = 0 pirs = target available = start_stock( ) master = terran( ) )
      exp = VALUE lcl_mrp=>tt_planned(
              ( material = 'Marauder'        quantity = 5 start = 315 finish = 420 )
              ( material = 'BarracksTechLab' quantity = 1 start = 297 finish = 315 plannedfor = 'Marauder' )
              ( material = 'Barracks'        quantity = 1 start = 251 finish = 297 plannedfor = 'BarracksTechLab' )
              ( material = 'SupplyDepot'     quantity = 1 start = 230 finish = 251 plannedfor = 'Barracks' ) ) ).
  ENDMETHOD.

  METHOD firmed_lots_in_key_order.
    " two firmed lots with the same dates, handed over in the wrong order. 3 due 420 take from the first by key
    " (late), 7 due 600 take its other 2 and the second lot (in time)
    lcl_mrp=>plan( EXPORTING clock     = 0
                             pirs      = VALUE #( ( material = 'Marine' quantity = 7 due = 600 )
                                                  ( material = 'Marine' quantity = 3 due = 420 ) )
                             available = VALUE #( BASE start_stock( ) ( material = 'Barracks' quantity = 1 ) )
                             firmed    = VALUE #( ( id = f2 material = 'Marine' quantity = 5 start = 450 finish = 540 )
                                                  ( id = f1 material = 'Marine' quantity = 5 start = 450 finish = 540 ) )
                             master    = terran( )
                   IMPORTING firmed_texts = DATA(texts)
                   RECEIVING result       = DATA(plan) ).
    cl_abap_unit_assert=>assert_initial( act = plan msg = 'the firmed lots cover both targets' ).
    cl_abap_unit_assert=>assert_equals(
      act = texts
      exp = VALUE lcl_mrp=>tt_firmed_texts( ( id = f1 exception = 'reschedule in to 420 s' ) ( id = f2 ) ) ).
  ENDMETHOD.

  METHOD firmed_rest_is_carried.
    " one firmed lot of 5: the first target takes 3, the second gets the other 2 and no more, so 2 are planned
    lcl_mrp=>plan( EXPORTING clock     = 0
                             pirs      = VALUE #( ( material = 'Marine' quantity = 3 due = 600 )
                                                  ( material = 'Marine' quantity = 4 due = 700 ) )
                             available = VALUE #( BASE start_stock( ) ( material = 'Barracks' quantity = 1 ) )
                             firmed    = VALUE #( ( id = f1 material = 'Marine' quantity = 5 start = 450 finish = 540 ) )
                             master    = terran( )
                   IMPORTING firmed_texts = DATA(texts)
                   RECEIVING result       = DATA(plan) ).
    cl_abap_unit_assert=>assert_equals(
      act = plan
      exp = VALUE lcl_mrp=>tt_planned( ( material = 'Marine' quantity = 2 start = 664 finish = 700 ) ) ).
    cl_abap_unit_assert=>assert_equals( act = texts exp = VALUE lcl_mrp=>tt_firmed_texts( ( id = f1 ) ) ).
  ENDMETHOD.

  METHOD past_beats_reschedule.
    " one text per order: the past comes before reschedule in
    DATA(target) = VALUE lcl_mrp=>tt_pirs( ( material = 'Marauder' quantity = 5 due = 420 ) ).
    DATA(stock) = VALUE lcl_mrp=>tt_available( BASE start_stock( ) ( material = 'Barracks' quantity = 1 )
                                               ( material = 'BarracksTechLab' quantity = 1 ) ).
    DATA(lot) = VALUE lcl_mrp=>tt_firmed( ( id = f1 material = 'Marauder' quantity = 5 start = 435 finish = 540 ) ).
    lcl_mrp=>plan( EXPORTING clock = 500 pirs = target available = stock firmed = lot master = terran( )
                   IMPORTING firmed_texts = DATA(started) ).
    cl_abap_unit_assert=>assert_equals( act = started[ 1 ]-exception exp = 'start in the past' ).
    lcl_mrp=>plan( EXPORTING clock = 600 pirs = target available = stock firmed = lot master = terran( )
                   IMPORTING firmed_texts = DATA(finished) ).
    cl_abap_unit_assert=>assert_equals( act = finished[ 1 ]-exception exp = 'finish in the past' ).
  ENDMETHOD.

  METHOD terran_supply.
    result = terran( ).
    result[ material = 'SCV' ]-supplycost               = 1.
    result[ material = 'Marine' ]-supplycost            = 1.
    result[ material = 'Marauder' ]-supplycost          = 2.
    result[ material = 'CommandCenter' ]-supplyprovided = 15.
    result[ material = 'CommandCenter' ]-mineralcost    = 300.
    result[ material = 'SupplyDepot' ]-supplyprovided   = 8.
    result[ material = 'SupplyDepot' ]-mineralcost      = 100.
  ENDMETHOD.

  METHOD no_source.
    result = terran_supply( ).
    result[ material = 'CommandCenter' ]-supplyprovided = 0.
    result[ material = 'SupplyDepot' ]-supplyprovided   = 0.
  ENDMETHOD.

  METHOD fresh_game.
    result = VALUE #( ( material = 'CommandCenter' quantity = 1 ) ( material = 'SCV' quantity = 12 ) ).
  ENDMETHOD.

  METHOD supply_example.
    " spec example 1: 12 of 15 used; the Barracks' depot gives 23; lot 1 takes 22; lot 2 needs 32: two depots, 39
    lcl_mrp=>plan( EXPORTING clock     = 0
                             pirs      = VALUE #( ( material = 'Marauder' quantity = 10 due = 540 ) )
                             available = fresh_game( )
                             master    = terran_supply( )
                   IMPORTING figures   = DATA(figures)
                   RECEIVING result    = DATA(plan) ).
    cl_abap_unit_assert=>assert_equals(
      act = plan
      exp = VALUE lcl_mrp=>tt_planned(
              ( material = 'Marauder'        quantity = 5 start = 435 finish = 540 )
              ( material = 'Marauder'        quantity = 5 start = 435 finish = 540 )
              ( material = 'BarracksTechLab' quantity = 1 start = 417 finish = 435 plannedfor = 'Marauder' )
              ( material = 'Barracks'        quantity = 1 start = 371 finish = 417 plannedfor = 'BarracksTechLab' )
              ( material = 'SupplyDepot'     quantity = 1 start = 350 finish = 371 plannedfor = 'Barracks' )
              ( material = 'SupplyDepot'     quantity = 1 start = 414 finish = 435 plannedfor = 'Marauder' )
              ( material = 'SupplyDepot'     quantity = 1 start = 414 finish = 435 plannedfor = 'Marauder' ) ) ).
    cl_abap_unit_assert=>assert_equals(
      act = figures
      exp = VALUE lcl_mrp=>ty_figures( used_now = 12 capacity_now = 15 used_planned = 32 capacity_planned = 39 ) ).
  ENDMETHOD.

  METHOD free_supply_plans_no_depot.
    lcl_mrp=>plan( EXPORTING clock     = 0
                             pirs      = VALUE #( ( material = 'Marine' quantity = 1 due = 300 ) )
                             available = VALUE #( BASE fresh_game( ) ( material = 'Barracks' quantity = 1 ) )
                             master    = terran_supply( )
                   IMPORTING figures   = DATA(figures)
                   RECEIVING result    = DATA(plan) ).
    cl_abap_unit_assert=>assert_equals(
      act = plan exp = VALUE lcl_mrp=>tt_planned( ( material = 'Marine' quantity = 1 start = 282 finish = 300 ) ) ).
    cl_abap_unit_assert=>assert_equals( act = figures-used_planned exp = 13 ).
    cl_abap_unit_assert=>assert_equals( act = figures-capacity_planned exp = 15 ).
  ENDMETHOD.

  METHOD late_receipt_does_not_cover.
    " capacity 23; the third Marine lot needs 27 at 210. The second Command Center (one is in stock) gives 15 at
    " 600: too late, so a depot
    lcl_mrp=>plan( EXPORTING clock     = 0
                             pirs      = VALUE #( ( material = 'CommandCenter' quantity = 2  due = 600 )
                                                  ( material = 'Marine'        quantity = 15 due = 300 ) )
                             available = VALUE #( BASE fresh_game( ) ( material = 'Barracks' quantity = 1 )
                                                  ( material = 'SupplyDepot' quantity = 1 ) )
                             master    = terran_supply( )
                   IMPORTING figures   = DATA(figures)
                   RECEIVING result    = DATA(plan) ).
    cl_abap_unit_assert=>assert_equals(
      act = plan
      exp = VALUE lcl_mrp=>tt_planned(
              ( material = 'Marine'        quantity = 5 start = 210 finish = 300 )
              ( material = 'Marine'        quantity = 5 start = 210 finish = 300 )
              ( material = 'Marine'        quantity = 5 start = 210 finish = 300 )
              ( material = 'CommandCenter' quantity = 1 start = 529 finish = 600 )
              ( material = 'SupplyDepot'   quantity = 1 start = 189 finish = 210 plannedfor = 'Marine' ) ) ).
    cl_abap_unit_assert=>assert_equals( act = figures-used_planned exp = 27 ).
    cl_abap_unit_assert=>assert_equals( act = figures-capacity_planned exp = 46 msg = '23 + 8 + 15' ).
  ENDMETHOD.

  METHOD open_orders_beyond_capacity.
    " no target: 5 released Marines need 17 of 15 now, so a depot is due at the clock (and late already)
    DATA(marines) = VALUE lcl_mrp=>tt_available( ( material = 'Marine' quantity = 5 ) ).
    lcl_mrp=>plan( EXPORTING clock     = 100
                             pirs      = VALUE #( )
                             available = VALUE #( BASE fresh_game( ) ( material = 'Barracks' quantity = 1 )
                                                  ( LINES OF marines ) )
                             open      = marines
                             master    = terran_supply( )
                   IMPORTING figures   = DATA(figures)
                   RECEIVING result    = DATA(plan) ).
    cl_abap_unit_assert=>assert_equals(
      act = plan
      exp = VALUE lcl_mrp=>tt_planned( ( material = 'SupplyDepot' quantity = 1 start = 79 finish = 100
                                         plannedfor = 'Marine' exception = 'start in the past' ) ) ).
    cl_abap_unit_assert=>assert_equals(
      act = figures
      exp = VALUE lcl_mrp=>ty_figures( used_now = 17 capacity_now = 15 used_planned = 17 capacity_planned = 23 ) ).
  ENDMETHOD.

  METHOD cap_of_200.
    " capacity 199 = 1 Command Center + 23 depots
    DATA(base) = VALUE lcl_mrp=>tt_available( ( material = 'CommandCenter' quantity = 1 )
                                              ( material = 'SupplyDepot' quantity = 23 )
                                              ( material = 'Barracks' quantity = 1 )
                                              ( material = 'BarracksTechLab' quantity = 1 ) ).
    " used 190, a lot needs 10: one depot lifts the capacity to 200 (not 207), the lot fits
    lcl_mrp=>plan( EXPORTING clock     = 0
                             pirs      = VALUE #( ( material = 'Marauder' quantity = 5 due = 300 ) )
                             available = VALUE #( BASE base ( material = 'SCV' quantity = 190 ) )
                             master    = terran_supply( )
                   IMPORTING figures   = DATA(fits)
                   RECEIVING result    = DATA(plan) ).
    cl_abap_unit_assert=>assert_equals(
      act = plan
      exp = VALUE lcl_mrp=>tt_planned(
              ( material = 'Marauder'    quantity = 5 start = 195 finish = 300 )
              ( material = 'SupplyDepot' quantity = 1 start = 174 finish = 195 plannedfor = 'Marauder' ) ) ).
    cl_abap_unit_assert=>assert_equals( act = fits-used_planned exp = 200 ).
    cl_abap_unit_assert=>assert_equals( act = fits-capacity_planned exp = 200 ).

    " used 199, a lot needs 2: one depot, capacity 200, used 201: short, and no second depot
    lcl_mrp=>plan( EXPORTING clock     = 0
                             pirs      = VALUE #( ( material = 'Marauder' quantity = 1 due = 300 ) )
                             available = VALUE #( BASE base ( material = 'SCV' quantity = 199 ) )
                             master    = terran_supply( )
                   IMPORTING figures   = DATA(over)
                   RECEIVING result    = plan ).
    cl_abap_unit_assert=>assert_equals(
      act = plan
      exp = VALUE lcl_mrp=>tt_planned(
              ( material = 'Marauder'    quantity = 1 start = 279 finish = 300 exception = 'short of supply' )
              ( material = 'SupplyDepot' quantity = 1 start = 258 finish = 279 plannedfor = 'Marauder' ) ) ).
    cl_abap_unit_assert=>assert_equals( act = over-used_planned exp = 201 ).
    cl_abap_unit_assert=>assert_equals( act = over-capacity_planned exp = 200 ).

    " 14 Command Centers provide 210: the capacity at the clock is 200
    lcl_mrp=>plan( EXPORTING clock     = 0
                             pirs      = VALUE #( )
                             available = VALUE #( ( material = 'CommandCenter' quantity = 14 ) )
                             master    = terran_supply( )
                   IMPORTING figures   = DATA(clipped) ).
    cl_abap_unit_assert=>assert_equals( act = clipped-capacity_now exp = 200 ).
  ENDMETHOD.

  METHOD no_source_stays_short.
    " no material provides supply: nothing to plan, the lot is short
    lcl_mrp=>plan( EXPORTING clock     = 0
                             pirs      = VALUE #( ( material = 'Marine' quantity = 5 due = 300 ) )
                             available = VALUE #( BASE fresh_game( ) ( material = 'Barracks' quantity = 1 ) )
                             master    = no_source( )
                   RECEIVING result    = DATA(plan) ).
    cl_abap_unit_assert=>assert_equals(
      act = plan
      exp = VALUE lcl_mrp=>tt_planned( ( material = 'Marine' quantity = 5 start = 210 finish = 300
                                         exception = 'short of supply' ) ) ).
    " open orders that are short have no planned order to carry the text: the figures show it
    DATA(marines) = VALUE lcl_mrp=>tt_available( ( material = 'Marine' quantity = 5 ) ).
    lcl_mrp=>plan( EXPORTING clock     = 0
                             pirs      = VALUE #( )
                             available = VALUE #( BASE fresh_game( ) ( LINES OF marines ) )
                             open      = marines
                             master    = no_source( )
                   IMPORTING figures   = DATA(figures)
                   RECEIVING result    = plan ).
    cl_abap_unit_assert=>assert_initial( plan ).
    cl_abap_unit_assert=>assert_equals(
      act = figures
      exp = VALUE lcl_mrp=>ty_figures( used_now = 17 capacity_now = 0 used_planned = 17 capacity_planned = 0 ) ).
  ENDMETHOD.

  METHOD source_per_company.
    cl_abap_unit_assert=>assert_equals( act = lcl_mrp=>supply_source( terran_supply( ) )-material exp = 'SupplyDepot' ).
    cl_abap_unit_assert=>assert_equals(
      act = lcl_mrp=>supply_source( VALUE #( ( material = 'Nexus' supplyprovided = 15 mineralcost = 400 )
                                             ( material = 'Pylon' supplyprovided = 8  mineralcost = 100 ) ) )-material
      exp = 'Pylon' ).
    cl_abap_unit_assert=>assert_equals(
      act = lcl_mrp=>supply_source( VALUE #( ( material = 'Hatchery' supplyprovided = 6 mineralcost = 300 )
                                             ( material = 'Overlord' supplyprovided = 8 mineralcost = 100 ) ) )-material
      exp = 'Overlord' ).
    cl_abap_unit_assert=>assert_equals(
      act = lcl_mrp=>supply_source( VALUE #( ( material = 'Alpha' supplyprovided = 8 mineralcost = 100 )
                                             ( material = 'Beta'  supplyprovided = 8 mineralcost = 100 ) ) )-material
      exp = 'Alpha' msg = 'a tie goes to the lower name' ).
    cl_abap_unit_assert=>assert_initial( act = lcl_mrp=>supply_source( no_source( ) ) msg = 'no provider, no source' ).
  ENDMETHOD.

  METHOD nobody_to_build_it.
    " a Command Center and 15 Marines, no SCV: the SCV needs a depot that only an SCV could build. No depot.
    lcl_mrp=>plan( EXPORTING clock     = 0
                             pirs      = VALUE #( ( material = 'SCV' quantity = 1 due = 100 ) )
                             available = VALUE #( ( material = 'CommandCenter' quantity = 1 )
                                                  ( material = 'Marine' quantity = 15 ) )
                             master    = terran_supply( )
                   IMPORTING figures   = DATA(figures)
                   RECEIVING result    = DATA(plan) ).
    cl_abap_unit_assert=>assert_equals(
      act = plan
      exp = VALUE lcl_mrp=>tt_planned( ( material = 'SCV' quantity = 1 start = 88 finish = 100
                                         exception = 'short of supply' ) ) ).
    cl_abap_unit_assert=>assert_equals( act = figures-used_planned exp = 16 ).
    cl_abap_unit_assert=>assert_equals( act = figures-capacity_planned exp = 15 ).
  ENDMETHOD.

  METHOD planned_worker_builds_depot.
    " a Command Center and no SCV. The Barracks' depot comes from the tech tree with its SCV, trained 338-350
    " before it builds the depot 350-371: that depot counts, 21 of 23
    DATA(town_hall) = VALUE lcl_mrp=>tt_available( ( material = 'CommandCenter' quantity = 1 ) ).
    lcl_mrp=>plan( EXPORTING clock     = 0
                             pirs      = VALUE #( ( material = 'Marauder' quantity = 10 due = 540 ) )
                             available = town_hall
                             master    = terran_supply( )
                   IMPORTING figures   = DATA(figures)
                   RECEIVING result    = DATA(plan) ).
    cl_abap_unit_assert=>assert_equals(
      act = plan
      exp = VALUE lcl_mrp=>tt_planned(
              ( material = 'Marauder'        quantity = 5 start = 435 finish = 540 )
              ( material = 'Marauder'        quantity = 5 start = 435 finish = 540 )
              ( material = 'BarracksTechLab' quantity = 1 start = 417 finish = 435 plannedfor = 'Marauder' )
              ( material = 'Barracks'        quantity = 1 start = 371 finish = 417 plannedfor = 'BarracksTechLab' )
              ( material = 'SupplyDepot'     quantity = 1 start = 350 finish = 371 plannedfor = 'Barracks' )
              ( material = 'SCV'             quantity = 1 start = 338 finish = 350 plannedfor = 'SupplyDepot' ) ) ).
    cl_abap_unit_assert=>assert_equals(
      act = figures
      exp = VALUE lcl_mrp=>ty_figures( used_now = 0 capacity_now = 15 used_planned = 21 capacity_planned = 23 ) ).
    " the walk itself adds no depot without a worker in stock or on order: lots 3 and 4 of 20 Marauders are short
    lcl_mrp=>plan( EXPORTING clock     = 0
                             pirs      = VALUE #( ( material = 'Marauder' quantity = 20 due = 540 ) )
                             available = town_hall
                             master    = terran_supply( )
                   IMPORTING figures   = figures
                   RECEIVING result    = plan ).
    cl_abap_unit_assert=>assert_equals( act = lines( plan ) exp = 8 msg = 'four lots and the chain, no depot added' ).
    cl_abap_unit_assert=>assert_initial( plan[ 2 ]-exception ).
    cl_abap_unit_assert=>assert_equals( act = plan[ 3 ]-exception exp = 'short of supply' ).
    cl_abap_unit_assert=>assert_equals( act = plan[ 4 ]-exception exp = 'short of supply' ).
    cl_abap_unit_assert=>assert_equals( act = figures-used_planned exp = 41 ).
    cl_abap_unit_assert=>assert_equals( act = figures-capacity_planned exp = 23 ).
  ENDMETHOD.

  METHOD blocked_worker_gives_nothing.
    " a Command Center and 15 Marines fill the 15 supply. The planned SCV is short itself (16 of 15), so the
    " depot it would build delivers nothing and the Marauder is short as well
    lcl_mrp=>plan( EXPORTING clock     = 0
                             pirs      = VALUE #( ( material = 'Marauder' quantity = 1 due = 540 ) )
                             available = VALUE #( ( material = 'CommandCenter' quantity = 1 )
                                                  ( material = 'Marine' quantity = 15 ) )
                             master    = terran_supply( )
                   IMPORTING figures   = DATA(figures)
                   RECEIVING result    = DATA(plan) ).
    cl_abap_unit_assert=>assert_equals(
      act = plan
      exp = VALUE lcl_mrp=>tt_planned(
              ( material = 'Marauder'        quantity = 1 start = 519 finish = 540 exception = 'short of supply' )
              ( material = 'BarracksTechLab' quantity = 1 start = 501 finish = 519 plannedfor = 'Marauder' )
              ( material = 'Barracks'        quantity = 1 start = 455 finish = 501 plannedfor = 'BarracksTechLab' )
              ( material = 'SupplyDepot'     quantity = 1 start = 434 finish = 455 plannedfor = 'Barracks' )
              ( material = 'SCV'             quantity = 1 start = 422 finish = 434 plannedfor = 'SupplyDepot'
                exception = 'short of supply' ) ) ).
    cl_abap_unit_assert=>assert_equals(
      act = figures
      exp = VALUE lcl_mrp=>ty_figures( used_now = 15 capacity_now = 15 used_planned = 18 capacity_planned = 15 ) ).
  ENDMETHOD.

  METHOD short_in_the_precedence.
    DATA(stock) = VALUE lcl_mrp=>tt_available( BASE fresh_game( ) ( material = 'Barracks' quantity = 1 ) ).
    " the past comes before short of supply
    cl_abap_unit_assert=>assert_equals(
      act = lcl_mrp=>plan( clock = 250 pirs = VALUE #( ( material = 'Marine' quantity = 5 due = 300 ) )
                           available = stock master = no_source( ) )
      exp = VALUE lcl_mrp=>tt_planned( ( material = 'Marine' quantity = 5 start = 210 finish = 300
                                         exception = 'start in the past' ) ) ).
    " short of supply comes before reschedule in
    lcl_mrp=>plan( EXPORTING clock     = 0
                             pirs      = VALUE #( ( material = 'Marine' quantity = 5 due = 300 ) )
                             available = stock
                             firmed    = VALUE #( ( id = f1 material = 'Marine' quantity = 5 start = 310 finish = 400 ) )
                             master    = no_source( )
                   IMPORTING firmed_texts = DATA(texts) ).
    cl_abap_unit_assert=>assert_equals( act = texts[ 1 ]-exception exp = 'short of supply' ).
  ENDMETHOD.
ENDCLASS.

CLASS ltc_mrp_actions DEFINITION FINAL FOR TESTING
  DURATION SHORT RISK LEVEL HARMLESS.
  PRIVATE SECTION.
    CONSTANTS game     TYPE sysuuid_x16 VALUE 'AD000000000000000000000000000001'.
    CONSTANTS division TYPE sysuuid_x16 VALUE 'AD000000000000000000000000000002'.
    CONSTANTS old      TYPE sysuuid_x16 VALUE 'AD000000000000000000000000000003'.
    CONSTANTS lot      TYPE sysuuid_x16 VALUE 'AD000000000000000000000000000004'.
    CLASS-DATA sql TYPE REF TO if_osql_test_environment.
    CLASS-METHODS class_setup.
    CLASS-METHODS class_teardown.
    METHODS setup.
    METHODS plan_requirement_creates_pir FOR TESTING RAISING cx_static_check.
    METHODS plan_requirement_refuses_bad FOR TESTING RAISING cx_static_check.
    METHODS plan_requirement_defaults FOR TESTING RAISING cx_static_check.
    METHODS run_mrp_replaces_old_plan FOR TESTING RAISING cx_static_check.
    METHODS convert_creates_released FOR TESTING RAISING cx_static_check.
    METHODS delete_removes_requirement FOR TESTING RAISING cx_static_check.
    CONSTANTS kept      TYPE sysuuid_x16 VALUE 'AD000000000000000000000000000009'.
    CONSTANTS division2 TYPE sysuuid_x16 VALUE 'AD00000000000000000000000000000A'.
    CONSTANTS kept2     TYPE sysuuid_x16 VALUE 'AD00000000000000000000000000000B'.
    METHODS firm_and_unfirm FOR TESTING RAISING cx_static_check.
    METHODS add_supply_materials.
    METHODS run_mrp_keeps_firmed FOR TESTING RAISING cx_static_check.
    METHODS run_mrp_supplies_open_orders FOR TESTING RAISING cx_static_check.
    METHODS run_mrp_two_divisions FOR TESTING RAISING cx_static_check.
ENDCLASS.

CLASS ltc_mrp_actions IMPLEMENTATION.
  METHOD class_setup.
    sql = cl_osql_test_environment=>create(
            VALUE #( ( 'ZSCE_GAME' ) ( 'ZSCE_DIVISION' ) ( 'ZSCE_PLANT' ) ( 'ZSCE_PRODORD' ) ( 'ZSCE_EVENT' )
                     ( 'ZSCE_MATERIAL' ) ( 'ZSCE_PIR' ) ( 'ZSCE_PLANORD' ) ) ).
  ENDMETHOD.

  METHOD class_teardown.
    sql->destroy( ).
  ENDMETHOD.

  METHOD setup.
    " the division is created in the test's LUW: READ ENTITIES and actions do not see rows committed into the doubles
    DATA materials TYPE STANDARD TABLE OF zsce_material WITH EMPTY KEY.
    sql->clear_doubles( ).
    ROLLBACK ENTITIES.
    materials = VALUE #( bukrs = '1000'
      ( material_uuid = 'AD0000000000000000000000000000A1' matnr = 'Marine' category = 'UNIT' build_seconds = 18
        produced_by = 'Barracks' )
      ( material_uuid = 'AD0000000000000000000000000000A2' matnr = 'Barracks' category = 'STRUCTURE' build_seconds = 46
        produced_by = 'SCV' ) ).
    sql->insert_test_data( materials ).
    MODIFY ENTITIES OF zi_scegame
      ENTITY game
        CREATE FIELDS ( gameuuid replayhash )
        WITH VALUE #( ( %cid = 'g1' gameuuid = game replayhash = 'MRP' ) )
        CREATE BY \_Division FIELDS ( divisionuuid companycode divisioncode )
        WITH VALUE #( ( %cid_ref = 'g1'
                        %target  = VALUE #( ( %cid = 'd1' divisionuuid = division  companycode = '1000' divisioncode = 'P1' )
                                            ( %cid = 'd2' divisionuuid = division2 companycode = '1000' divisioncode = 'P2' ) ) ) )
      MAPPED DATA(mapped) FAILED DATA(failed) REPORTED DATA(reported).
    cl_abap_unit_assert=>assert_initial( act = failed msg = 'seed must be accepted' ).
  ENDMETHOD.

  METHOD plan_requirement_creates_pir.
    MODIFY ENTITIES OF zi_scegame
      ENTITY division
        EXECUTE planrequirement
          FROM VALUE #( ( divisionuuid = division %param = VALUE #( material = 'Marine' quantity = 20 dueminute = 8 ) ) )
      FAILED DATA(failed) REPORTED DATA(reported).
    COMMIT ENTITIES RESPONSE OF zi_scegame
      FAILED DATA(commit_failed) REPORTED DATA(commit_reported).

    cl_abap_unit_assert=>assert_initial( act = failed-division msg = 'a valid requirement must not fail' ).
    cl_abap_unit_assert=>assert_initial( act = commit_failed msg = 'the requirement must save' ).
    SELECT SINGLE matnr, quantity, due_seconds FROM zsce_pir WHERE division_uuid = @division INTO @DATA(pir).
    cl_abap_unit_assert=>assert_equals( act = pir-matnr exp = 'Marine' ).
    cl_abap_unit_assert=>assert_equals( act = pir-quantity exp = 20 ).
    cl_abap_unit_assert=>assert_equals( act = pir-due_seconds exp = 480 msg = 'minute 8 = 480 game seconds' ).
    cl_abap_unit_assert=>assert_equals( act = reported-division[ 1 ]-%msg->if_message~get_text( )
                                        exp = `20 × Marine due minute 8` ).
  ENDMETHOD.

  METHOD plan_requirement_refuses_bad.
    MODIFY ENTITIES OF zi_scegame
      ENTITY division
        EXECUTE planrequirement
          FROM VALUE #( ( divisionuuid = division %param = VALUE #( material = 'Marine' quantity = 0 dueminute = 8 ) ) )
      FAILED DATA(zero).
    MODIFY ENTITIES OF zi_scegame
      ENTITY division
        EXECUTE planrequirement
          FROM VALUE #( ( divisionuuid = division %param = VALUE #( material = 'Marine' quantity = 5 dueminute = -1 ) ) )
      FAILED DATA(past).
    MODIFY ENTITIES OF zi_scegame
      ENTITY division
        EXECUTE planrequirement
          FROM VALUE #( ( divisionuuid = division %param = VALUE #( material = 'Zergling' quantity = 5 dueminute = 8 ) ) )
      FAILED DATA(foreign).

    cl_abap_unit_assert=>assert_not_initial( act = zero-division msg = 'quantity 0 must fail' ).
    cl_abap_unit_assert=>assert_not_initial( act = past-division msg = 'a negative minute must fail' ).
    cl_abap_unit_assert=>assert_not_initial( act = foreign-division msg = 'a material outside the company must fail' ).
    COMMIT ENTITIES.
    SELECT COUNT( * ) FROM zsce_pir INTO @DATA(pirs).
    cl_abap_unit_assert=>assert_equals( act = pirs exp = 0 msg = 'nothing planned' ).
  ENDMETHOD.

  METHOD plan_requirement_defaults.
    DATA events TYPE STANDARD TABLE OF zsce_event WITH EMPTY KEY.
    events = VALUE #( ( event_uuid = 'AD0000000000000000000000000000E1' division_uuid = division game_seconds = 125
                        mvt_type = '501' matnr = 'MINERAL' quantity = 40 mineral_value = 40 ) ).
    sql->insert_test_data( events ).

    READ ENTITIES OF zi_scegame
      ENTITY division
        EXECUTE getdefaultsforplanrequirement
          FROM VALUE #( ( divisionuuid = division ) )
        RESULT DATA(defaults).

    cl_abap_unit_assert=>assert_equals( act = lines( defaults ) exp = 1 msg = 'one default row per key' ).
    cl_abap_unit_assert=>assert_equals( act = defaults[ 1 ]-%param-quantity exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = defaults[ 1 ]-%param-dueminute exp = 7 msg = 'game clock 125 s = minute 2, plus 5' ).
    cl_abap_unit_assert=>assert_equals( act = defaults[ 1 ]-%param-divisionuuid exp = division
                                        msg = 'the bound division is passed to the value help' ).
  ENDMETHOD.

  METHOD run_mrp_replaces_old_plan.
    DATA events TYPE STANDARD TABLE OF zsce_event WITH EMPTY KEY.
    events = VALUE #( ( event_uuid = 'AD0000000000000000000000000000E2' division_uuid = division game_seconds = 100
                        mvt_type = '501' matnr = 'MINERAL' quantity = 40 mineral_value = 40 ) ).
    sql->insert_test_data( events ).
    " 5 Marines by 300 s; the Barracks is on order (covers the producer), a CANCELLING Marine covers nothing,
    " and a planned order from an earlier run must go
    MODIFY ENTITIES OF zi_scegame
      ENTITY division
        CREATE BY \_requirement FIELDS ( requirementuuid material quantity dueseconds )
        WITH VALUE #( ( divisionuuid = division
                        %target = VALUE #( ( %cid = 'r1' requirementuuid = 'AD000000000000000000000000000005'
                                             material = 'Marine' quantity = 5 dueseconds = 300 ) ) ) )
        CREATE BY \_plannedorder FIELDS ( plannedorderuuid material quantity startseconds finishseconds )
        WITH VALUE #( ( divisionuuid = division
                        %target = VALUE #( ( %cid = 'p1' plannedorderuuid = old material = 'Marine' quantity = 1
                                             startseconds = 1 finishseconds = 2 ) ) ) )
        CREATE BY \_prodorder FIELDS ( orderuuid material quantity orderstatus )
        WITH VALUE #( ( divisionuuid = division
                        %target = VALUE #( ( %cid = 'o1' orderuuid = 'AD000000000000000000000000000006'
                                             material = 'Barracks' quantity = 1 orderstatus = 'RELEASED' )
                                           ( %cid = 'o2' orderuuid = 'AD000000000000000000000000000007'
                                             material = 'Marine' quantity = 1 orderstatus = 'CANCELLING' ) ) ) )
      FAILED DATA(seed_failed).
    cl_abap_unit_assert=>assert_initial( act = seed_failed msg = 'seed must be accepted' ).

    MODIFY ENTITIES OF zi_scegame
      ENTITY division
        EXECUTE runmrp FROM VALUE #( ( divisionuuid = division ) )
      FAILED DATA(failed) REPORTED DATA(reported).
    COMMIT ENTITIES RESPONSE OF zi_scegame
      FAILED DATA(commit_failed) REPORTED DATA(commit_reported).

    cl_abap_unit_assert=>assert_initial( act = failed-division msg = 'the run must not fail' ).
    cl_abap_unit_assert=>assert_initial( act = commit_failed msg = 'the plan must save' ).
    SELECT matnr, quantity, start_seconds, finish_seconds, planned_for, exception_text FROM zsce_planord
      WHERE division_uuid = @division
      INTO TABLE @DATA(plan).
    cl_abap_unit_assert=>assert_equals( act = lines( plan ) exp = 1 msg = 'the old planned order is gone, one lot is new' ).
    cl_abap_unit_assert=>assert_equals( act = plan[ 1 ]-matnr exp = 'Marine' ).
    cl_abap_unit_assert=>assert_equals( act = plan[ 1 ]-quantity exp = 5 msg = 'CANCELLING covers nothing' ).
    cl_abap_unit_assert=>assert_equals( act = plan[ 1 ]-start_seconds exp = 210 ).
    cl_abap_unit_assert=>assert_equals( act = plan[ 1 ]-finish_seconds exp = 300 ).
    cl_abap_unit_assert=>assert_initial( act = plan[ 1 ]-planned_for ).
    cl_abap_unit_assert=>assert_initial( act = plan[ 1 ]-exception_text msg = 'clock 100 s is before the start' ).
    cl_abap_unit_assert=>assert_equals( act = reported-division[ 1 ]-%msg->if_message~get_text( )
                                        exp = `MRP at 100 s: planned orders 1, exceptions 0` ).
  ENDMETHOD.

  METHOD convert_creates_released.
    MODIFY ENTITIES OF zi_scegame
      ENTITY division
        CREATE BY \_plannedorder FIELDS ( plannedorderuuid material quantity startseconds finishseconds )
        WITH VALUE #( ( divisionuuid = division
                        %target = VALUE #( ( %cid = 'p1' plannedorderuuid = lot material = 'Marine' quantity = 5
                                             startseconds = 210 finishseconds = 300 ) ) ) )
      FAILED DATA(seed_failed).
    cl_abap_unit_assert=>assert_initial( act = seed_failed msg = 'seed must be accepted' ).

    " a planned order a newer run deleted: nothing to convert
    MODIFY ENTITIES OF zi_scegame
      ENTITY plannedorder
        EXECUTE convertorder FROM VALUE #( ( plannedorderuuid = old ) )
      FAILED DATA(gone).
    cl_abap_unit_assert=>assert_not_initial( act = gone-plannedorder msg = 'an unknown planned order must fail' ).

    MODIFY ENTITIES OF zi_scegame
      ENTITY plannedorder
        EXECUTE convertorder FROM VALUE #( ( plannedorderuuid = lot ) )
      FAILED DATA(failed) REPORTED DATA(reported).
    COMMIT ENTITIES RESPONSE OF zi_scegame
      FAILED DATA(commit_failed) REPORTED DATA(commit_reported).

    cl_abap_unit_assert=>assert_initial( act = failed-plannedorder msg = 'the conversion must not fail' ).
    cl_abap_unit_assert=>assert_initial( act = commit_failed msg = 'the conversion must save' ).
    SELECT COUNT( * ) FROM zsce_prodord
      WHERE division_uuid = @division AND matnr = 'Marine' AND quantity = 1 AND order_status = 'RELEASED'
        AND status_text = 'converted from planned order'
      INTO @DATA(released).
    cl_abap_unit_assert=>assert_equals( act = released exp = 5 msg = 'a lot of 5 = five single-unit orders for the bot' ).
    SELECT COUNT( * ) FROM zsce_planord INTO @DATA(remaining).
    cl_abap_unit_assert=>assert_equals( act = remaining exp = 0 msg = 'the planned order is gone' ).
  ENDMETHOD.

  METHOD delete_removes_requirement.
    MODIFY ENTITIES OF zi_scegame
      ENTITY division
        CREATE BY \_requirement FIELDS ( requirementuuid material quantity dueseconds )
        WITH VALUE #( ( divisionuuid = division
                        %target = VALUE #( ( %cid = 'r1' requirementuuid = 'AD000000000000000000000000000008'
                                             material = 'Marine' quantity = 5 dueseconds = 300 ) ) ) )
      FAILED DATA(seed_failed).
    cl_abap_unit_assert=>assert_initial( act = seed_failed msg = 'seed must be accepted' ).

    MODIFY ENTITIES OF zi_scegame
      ENTITY requirement
        EXECUTE deleterequirement FROM VALUE #( ( requirementuuid = 'AD000000000000000000000000000008' ) )
      FAILED DATA(failed) REPORTED DATA(reported).
    COMMIT ENTITIES RESPONSE OF zi_scegame
      FAILED DATA(commit_failed) REPORTED DATA(commit_reported).

    cl_abap_unit_assert=>assert_initial( act = failed-requirement msg = 'the delete must not fail' ).
    cl_abap_unit_assert=>assert_initial( act = commit_failed msg = 'the delete must save' ).
    SELECT COUNT( * ) FROM zsce_pir INTO @DATA(pirs).
    cl_abap_unit_assert=>assert_equals( act = pirs exp = 0 msg = 'the requirement is gone' ).
  ENDMETHOD.

  METHOD firm_and_unfirm.
    " both actions in one LUW: after COMMIT ENTITIES an action no longer sees the row in the test doubles
    MODIFY ENTITIES OF zi_scegame
      ENTITY division
        CREATE BY \_plannedorder FIELDS ( plannedorderuuid material quantity startseconds finishseconds firmed )
        WITH VALUE #( ( divisionuuid = division
                        %target = VALUE #( ( %cid = 'p1' plannedorderuuid = lot material = 'Marine' quantity = 5
                                             startseconds = 210 finishseconds = 300 )
                                           ( %cid = 'p2' plannedorderuuid = kept material = 'Marine' quantity = 5
                                             startseconds = 310 finishseconds = 400 firmed = abap_true ) ) ) )
      FAILED DATA(seed_failed).
    cl_abap_unit_assert=>assert_initial( act = seed_failed msg = 'seed must be accepted' ).

    " a planned order a newer run deleted: nothing to firm
    MODIFY ENTITIES OF zi_scegame
      ENTITY plannedorder
        EXECUTE firmorder FROM VALUE #( ( plannedorderuuid = old ) )
      FAILED DATA(gone).
    cl_abap_unit_assert=>assert_not_initial( act = gone-plannedorder msg = 'an unknown planned order must fail' ).

    MODIFY ENTITIES OF zi_scegame
      ENTITY plannedorder
        EXECUTE firmorder FROM VALUE #( ( plannedorderuuid = lot ) )
        EXECUTE unfirmorder FROM VALUE #( ( plannedorderuuid = kept ) )
      FAILED DATA(failed).
    COMMIT ENTITIES RESPONSE OF zi_scegame FAILED DATA(commit_failed).
    cl_abap_unit_assert=>assert_initial( act = failed-plannedorder msg = 'firming and unfirming must not fail' ).
    cl_abap_unit_assert=>assert_initial( act = commit_failed msg = 'both must save' ).

    SELECT SINGLE firmed, start_seconds, finish_seconds FROM zsce_planord WHERE planord_uuid = @lot INTO @DATA(row).
    cl_abap_unit_assert=>assert_equals( act = row-firmed exp = abap_true msg = 'firmed' ).
    cl_abap_unit_assert=>assert_equals( act = row-start_seconds exp = 210 msg = 'firming changes nothing else' ).
    cl_abap_unit_assert=>assert_equals( act = row-finish_seconds exp = 300 ).
    SELECT SINGLE firmed FROM zsce_planord WHERE planord_uuid = @kept INTO @DATA(firmed).
    cl_abap_unit_assert=>assert_equals( act = firmed exp = abap_false msg = 'unfirmed' ).
  ENDMETHOD.

  METHOD add_supply_materials.
    " on top of setup's Marine and Barracks: a unit that costs supply, the two providers and the worker
    DATA materials TYPE STANDARD TABLE OF zsce_material WITH EMPTY KEY.
    materials = VALUE #( bukrs = '1000'
      ( material_uuid = 'AD0000000000000000000000000000A3' matnr = 'Marauder' category = 'UNIT'
        build_seconds = 21 produced_by = 'Barracks' supply_cost = 2 )
      ( material_uuid = 'AD0000000000000000000000000000A4' matnr = 'CommandCenter' category = 'STRUCTURE'
        build_seconds = 71 produced_by = 'SCV' supply_provided = 15 mineral_cost = 300 )
      ( material_uuid = 'AD0000000000000000000000000000A5' matnr = 'SupplyDepot' category = 'STRUCTURE'
        build_seconds = 21 produced_by = 'SCV' supply_provided = 8 mineral_cost = 100 )
      ( material_uuid = 'AD0000000000000000000000000000A6' matnr = 'SCV' category = 'UNIT'
        build_seconds = 12 produced_by = 'CommandCenter' supply_cost = 1 ) ).
    sql->insert_test_data( materials ).
  ENDMETHOD.

  METHOD run_mrp_keeps_firmed.
    DATA events TYPE STANDARD TABLE OF zsce_event WITH EMPTY KEY.
    events = VALUE #( ( event_uuid = 'AD0000000000000000000000000000E3' division_uuid = division game_seconds = 100
                        mvt_type = '501' matnr = 'MINERAL' quantity = 40 mineral_value = 40 ) ).
    sql->insert_test_data( events ).
    add_supply_materials( ).
    " a firmed lot finishing at 490 with a stale text, an unfirmed order of an earlier run; the Barracks and a
    " Command Center (capacity 15) are on order
    MODIFY ENTITIES OF zi_scegame
      ENTITY division
        CREATE BY \_requirement FIELDS ( requirementuuid material quantity dueseconds )
        WITH VALUE #( ( divisionuuid = division
                        %target = VALUE #( ( %cid = 'r1' requirementuuid = 'AD000000000000000000000000000005'
                                             material = 'Marauder' quantity = 5 dueseconds = 300 ) ) ) )
        CREATE BY \_plannedorder
          FIELDS ( plannedorderuuid material quantity startseconds finishseconds exceptiontext firmed )
        WITH VALUE #( ( divisionuuid = division
                        %target = VALUE #( ( %cid = 'p1' plannedorderuuid = kept material = 'Marauder' quantity = 5
                                             startseconds = 400 finishseconds = 490 exceptiontext = 'stale'
                                             firmed = abap_true )
                                           ( %cid = 'p2' plannedorderuuid = old material = 'Marauder' quantity = 1
                                             startseconds = 1 finishseconds = 2 ) ) ) )
        CREATE BY \_prodorder FIELDS ( orderuuid material quantity orderstatus )
        WITH VALUE #( ( divisionuuid = division
                        %target = VALUE #( ( %cid = 'o1' orderuuid = 'AD000000000000000000000000000006'
                                             material = 'Barracks' quantity = 1 orderstatus = 'RELEASED' )
                                           ( %cid = 'o2' orderuuid = 'AD000000000000000000000000000007'
                                             material = 'CommandCenter' quantity = 1 orderstatus = 'STARTED' ) ) ) )
      FAILED DATA(seed_failed).
    cl_abap_unit_assert=>assert_initial( act = seed_failed msg = 'seed must be accepted' ).

    MODIFY ENTITIES OF zi_scegame
      ENTITY division
        EXECUTE runmrp FROM VALUE #( ( divisionuuid = division ) )
      FAILED DATA(failed) REPORTED DATA(reported).
    COMMIT ENTITIES RESPONSE OF zi_scegame FAILED DATA(commit_failed).

    cl_abap_unit_assert=>assert_initial( act = failed-division msg = 'the run must not fail' ).
    cl_abap_unit_assert=>assert_initial( act = commit_failed msg = 'the plan must save' ).
    SELECT planord_uuid, quantity, start_seconds, finish_seconds, exception_text, firmed FROM zsce_planord
      WHERE division_uuid = @division
      INTO TABLE @DATA(plan).
    cl_abap_unit_assert=>assert_equals( act = lines( plan ) exp = 1 msg = 'the firmed lot covers the target' ).
    cl_abap_unit_assert=>assert_equals( act = plan[ 1 ]-planord_uuid exp = kept msg = 'kept with its key' ).
    cl_abap_unit_assert=>assert_equals( act = plan[ 1 ]-start_seconds exp = 400 ).
    cl_abap_unit_assert=>assert_equals( act = plan[ 1 ]-finish_seconds exp = 490 ).
    cl_abap_unit_assert=>assert_equals( act = plan[ 1 ]-firmed exp = abap_true ).
    cl_abap_unit_assert=>assert_equals( act = plan[ 1 ]-exception_text exp = 'reschedule in to 300 s' ).
    cl_abap_unit_assert=>assert_equals( act = lines( reported-division ) exp = 2 msg = 'two messages' ).
    cl_abap_unit_assert=>assert_equals( act = reported-division[ 1 ]-%msg->if_message~get_text( )
                                        exp = `MRP at 100 s: planned orders 1, exceptions 1` ).
    " the firmed lot's 5 x 2 supply is counted: 10 of the 15 the Command Center on order provides
    cl_abap_unit_assert=>assert_equals( act = reported-division[ 2 ]-%msg->if_message~get_text( )
                                        exp = `Supply 0 of 15 now, 10 of 15 planned` ).
  ENDMETHOD.

  METHOD run_mrp_supplies_open_orders.
    " no target. On order: a Command Center (15), an SCV (1) and 8 Marauders (16): 17 of 15, so a depot at the clock
    DATA events TYPE STANDARD TABLE OF zsce_event WITH EMPTY KEY.
    events = VALUE #( ( event_uuid = 'AD0000000000000000000000000000E4' division_uuid = division game_seconds = 100
                        mvt_type = '501' matnr = 'MINERAL' quantity = 40 mineral_value = 40 ) ).
    sql->insert_test_data( events ).
    add_supply_materials( ).
    MODIFY ENTITIES OF zi_scegame
      ENTITY division
        CREATE BY \_prodorder FIELDS ( orderuuid material quantity orderstatus )
        WITH VALUE #( ( divisionuuid = division
                        %target = VALUE #( ( %cid = 'o1' orderuuid = 'AD00000000000000000000000000000D'
                                             material = 'CommandCenter' quantity = 1 orderstatus = 'STARTED' )
                                           ( %cid = 'o2' orderuuid = 'AD00000000000000000000000000000E'
                                             material = 'SCV' quantity = 1 orderstatus = 'STARTED' )
                                           ( %cid = 'o3' orderuuid = 'AD00000000000000000000000000000F'
                                             material = 'Marauder' quantity = 8 orderstatus = 'RELEASED' )
                                           ( %cid = 'o4' orderuuid = 'AD000000000000000000000000000010'
                                             material = 'Marauder' quantity = 9 orderstatus = 'CANCELLING' ) ) ) )
      FAILED DATA(seed_failed).
    cl_abap_unit_assert=>assert_initial( act = seed_failed msg = 'seed must be accepted' ).

    MODIFY ENTITIES OF zi_scegame
      ENTITY division
        EXECUTE runmrp FROM VALUE #( ( divisionuuid = division ) )
      FAILED DATA(failed) REPORTED DATA(reported).
    COMMIT ENTITIES RESPONSE OF zi_scegame FAILED DATA(commit_failed).

    cl_abap_unit_assert=>assert_initial( act = failed-division msg = 'the run must not fail' ).
    cl_abap_unit_assert=>assert_initial( act = commit_failed msg = 'the plan must save' ).
    SELECT matnr, quantity, start_seconds, finish_seconds, planned_for, exception_text FROM zsce_planord
      WHERE division_uuid = @division
      INTO TABLE @DATA(plan).
    cl_abap_unit_assert=>assert_equals( act = lines( plan ) exp = 1 msg = 'one depot' ).
    cl_abap_unit_assert=>assert_equals( act = plan[ 1 ]-matnr exp = 'SupplyDepot' ).
    cl_abap_unit_assert=>assert_equals( act = plan[ 1 ]-start_seconds exp = 79 ).
    cl_abap_unit_assert=>assert_equals( act = plan[ 1 ]-finish_seconds exp = 100 ).
    cl_abap_unit_assert=>assert_equals( act = plan[ 1 ]-planned_for exp = 'Marauder' ).
    cl_abap_unit_assert=>assert_equals( act = plan[ 1 ]-exception_text exp = 'start in the past' ).
    cl_abap_unit_assert=>assert_equals( act = reported-division[ 1 ]-%msg->if_message~get_text( )
                                        exp = `MRP at 100 s: planned orders 1, exceptions 1` ).
    cl_abap_unit_assert=>assert_equals( act = reported-division[ 2 ]-%msg->if_message~get_text( )
                                        exp = `Supply 17 of 15 now, 17 of 23 planned` msg = 'CANCELLING counts for nothing' ).
  ENDMETHOD.

  METHOD run_mrp_two_divisions.
    " each division has a firmed Marine lot and its own open Barracks; one call runs both
    MODIFY ENTITIES OF zi_scegame
      ENTITY division
        CREATE BY \_plannedorder FIELDS ( plannedorderuuid material quantity startseconds finishseconds firmed )
        WITH VALUE #( ( divisionuuid = division
                        %target = VALUE #( ( %cid = 'p1' plannedorderuuid = kept material = 'Marine' quantity = 5
                                             startseconds = 210 finishseconds = 300 firmed = abap_true ) ) )
                      ( divisionuuid = division2
                        %target = VALUE #( ( %cid = 'p2' plannedorderuuid = kept2 material = 'Marine' quantity = 5
                                             startseconds = 310 finishseconds = 400 firmed = abap_true ) ) ) )
        CREATE BY \_prodorder FIELDS ( orderuuid material quantity orderstatus )
        WITH VALUE #( ( divisionuuid = division
                        %target = VALUE #( ( %cid = 'o1' orderuuid = 'AD00000000000000000000000000000C'
                                             material = 'Barracks' quantity = 1 orderstatus = 'RELEASED' ) ) ) )
      FAILED DATA(seed_failed).
    cl_abap_unit_assert=>assert_initial( act = seed_failed msg = 'seed must be accepted' ).

    MODIFY ENTITIES OF zi_scegame
      ENTITY division
        EXECUTE runmrp FROM VALUE #( ( divisionuuid = division ) ( divisionuuid = division2 ) )
      FAILED DATA(failed).
    COMMIT ENTITIES RESPONSE OF zi_scegame FAILED DATA(commit_failed).
    cl_abap_unit_assert=>assert_initial( act = failed-division msg = 'the run must not fail' ).
    cl_abap_unit_assert=>assert_initial( act = commit_failed msg = 'the plan must save' ).

    SELECT division_uuid, matnr, planord_uuid, firmed FROM zsce_planord
      ORDER BY division_uuid, matnr
      INTO TABLE @DATA(plan).
    " division 1: its Barracks is on order, so only the firmed lot. Division 2 has none: a Barracks is planned,
    " and the SCV to build it (the test's material master does not know the SCV, so it has no producer)
    cl_abap_unit_assert=>assert_equals( act = lines( plan ) exp = 4 ).
    cl_abap_unit_assert=>assert_equals( act = plan[ 1 ]-planord_uuid exp = kept ).
    cl_abap_unit_assert=>assert_equals( act = plan[ 2 ]-matnr exp = 'Barracks' ).
    cl_abap_unit_assert=>assert_equals( act = plan[ 2 ]-division_uuid exp = division2 ).
    cl_abap_unit_assert=>assert_equals( act = plan[ 3 ]-planord_uuid exp = kept2 ).
    cl_abap_unit_assert=>assert_equals( act = plan[ 4 ]-matnr exp = 'SCV' ).
    cl_abap_unit_assert=>assert_equals( act = plan[ 4 ]-division_uuid exp = division2 ).
  ENDMETHOD.
ENDCLASS.
CLASS ltc_pm_rules DEFINITION FINAL FOR TESTING
  DURATION SHORT RISK LEVEL HARMLESS.
  PRIVATE SECTION.
    METHODS transitions FOR TESTING.
    METHODS outcomes FOR TESTING.
    METHODS conditions FOR TESTING.
    METHODS cost_postings FOR TESTING.
    METHODS posting IMPORTING mvt          TYPE zsce_event-mvt_type DEFAULT '261'
                              material     TYPE zsce_event-matnr DEFAULT 'MINERAL'
                              quantity     TYPE i DEFAULT 5
                              minerals     TYPE i DEFAULT 5
                              gas          TYPE i DEFAULT 0
                              plant        TYPE sysuuid_x16 OPTIONAL
                              source       TYPE zsce_event-event_source DEFAULT 'LIVE'
                              division     TYPE sysuuid_x16 DEFAULT 'D1D1D1D1D1D1D1D1D1D1D1D1D1D1D1D1'
                    RETURNING VALUE(error) TYPE string.
ENDCLASS.

CLASS ltc_pm_rules IMPLEMENTATION.
  METHOD transitions.
    " allowed, the jumps and the repeated report included
    LOOP AT VALUE string_table( ( `RELEASED>STARTED` ) ( `RELEASED>CONFIRMED` ) ( `RELEASED>CANCELLED` ) ( `RELEASED>RELEASED` )
                                ( `STARTED>RELEASED` ) ( `STARTED>CONFIRMED` ) ( `STARTED>CANCELLED` ) ( `STARTED>STARTED` )
                                ( `CANCELLING>CANCELLED` ) ( `CANCELLING>CONFIRMED` )
                                ( `CONFIRMED>CONFIRMED` ) ( `CANCELLED>CANCELLED` ) ) INTO DATA(allowed).
      SPLIT allowed AT '>' INTO DATA(from) DATA(to).
      cl_abap_unit_assert=>assert_initial( act = lcl_pm=>transition( from = CONV #( from ) to = CONV #( to ) ) msg = allowed ).
    ENDLOOP.
    " refused: a finished order never moves, a cancel request is never taken back, CANCELLING is SAP's alone
    LOOP AT VALUE string_table( ( `CONFIRMED>STARTED` ) ( `CONFIRMED>RELEASED` ) ( `CONFIRMED>CANCELLED` )
                                ( `CANCELLED>RELEASED` ) ( `CANCELLED>STARTED` ) ( `CANCELLED>CONFIRMED` )
                                ( `CANCELLING>RELEASED` ) ( `CANCELLING>STARTED` )
                                ( `STARTED>CANCELLING` ) ( `RELEASED>SCRAPPED` ) ( `RELEASED>` ) ) INTO DATA(refused).
      SPLIT refused AT '>' INTO from to.
      cl_abap_unit_assert=>assert_not_initial( act = lcl_pm=>transition( from = CONV #( from ) to = CONV #( to ) ) msg = refused ).
    ENDLOOP.
    cl_abap_unit_assert=>assert_equals( act = lcl_pm=>transition( from = 'CONFIRMED' to = 'STARTED' ) exp = `Order already CONFIRMED` ).
  ENDMETHOD.

  METHOD outcomes.
    cl_abap_unit_assert=>assert_initial( act = lcl_pm=>outcome( status = 'CONFIRMED' outcome = '' ) ).
    cl_abap_unit_assert=>assert_initial( act = lcl_pm=>outcome( status = 'CONFIRMED' outcome = 'CLOSED' ) ).
    cl_abap_unit_assert=>assert_initial( act = lcl_pm=>outcome( status = 'CANCELLED' outcome = 'OPEN' ) ).
    cl_abap_unit_assert=>assert_initial( act = lcl_pm=>outcome( status = 'CANCELLED' outcome = 'CLOSED' ) ).
    cl_abap_unit_assert=>assert_initial( act = lcl_pm=>outcome( status = 'STARTED' outcome = '' ) ).
    cl_abap_unit_assert=>assert_initial( act = lcl_pm=>outcome( status = 'RELEASED' outcome = '' ) ).
    cl_abap_unit_assert=>assert_not_initial( act = lcl_pm=>outcome( status = 'CONFIRMED' outcome = 'OPEN' ) msg = 'a repair closes' ).
    cl_abap_unit_assert=>assert_not_initial( act = lcl_pm=>outcome( status = 'CANCELLED' outcome = '' ) msg = 'a cancel names the outcome' ).
    cl_abap_unit_assert=>assert_not_initial( act = lcl_pm=>outcome( status = 'CANCELLED' outcome = 'IN_PROCESS' ) ).
    cl_abap_unit_assert=>assert_not_initial( act = lcl_pm=>outcome( status = 'STARTED' outcome = 'CLOSED' ) ).
    cl_abap_unit_assert=>assert_not_initial( act = lcl_pm=>outcome( status = 'RELEASED' outcome = 'OPEN' ) ).
  ENDMETHOD.

  METHOD conditions.
    cl_abap_unit_assert=>assert_initial( act = lcl_pm=>condition( priority = '1' health = 0 healthmax = 400 ) ).
    cl_abap_unit_assert=>assert_initial( act = lcl_pm=>condition( priority = '3' health = 400 healthmax = 400 ) ).
    cl_abap_unit_assert=>assert_not_initial( act = lcl_pm=>condition( priority = '0' health = 100 healthmax = 400 ) ).
    cl_abap_unit_assert=>assert_not_initial( act = lcl_pm=>condition( priority = '4' health = 100 healthmax = 400 ) ).
    cl_abap_unit_assert=>assert_not_initial( act = lcl_pm=>condition( priority = ' ' health = 100 healthmax = 400 ) ).
    cl_abap_unit_assert=>assert_not_initial( act = lcl_pm=>condition( priority = '2' health = 401 healthmax = 400 ) ).
    cl_abap_unit_assert=>assert_not_initial( act = lcl_pm=>condition( priority = '2' health = -1 healthmax = 400 ) ).
    cl_abap_unit_assert=>assert_not_initial( act = lcl_pm=>condition( priority = '2' health = 0 healthmax = 0 ) ).
  ENDMETHOD.

  METHOD posting.
    error = lcl_pm=>cost_posting( division = 'D1D1D1D1D1D1D1D1D1D1D1D1D1D1D1D1'
                                  event    = VALUE #( division_uuid = division mvt_type = mvt matnr = material
                                                      quantity = quantity mineral_value = minerals gas_value = gas
                                                      plant_uuid = plant event_source = source ) ).
  ENDMETHOD.

  METHOD cost_postings.
    cl_abap_unit_assert=>assert_initial( act = posting( ) ).
    cl_abap_unit_assert=>assert_initial( act = posting( material = 'VESPENE' quantity = 3 minerals = 0 gas = 3 ) ).
    cl_abap_unit_assert=>assert_not_initial( act = posting( division = 'D2D2D2D2D2D2D2D2D2D2D2D2D2D2D2D2' ) msg = 'other division' ).
    cl_abap_unit_assert=>assert_not_initial( act = posting( mvt = '262' ) msg = 'the game refunds no repair' ).
    cl_abap_unit_assert=>assert_not_initial( act = posting( mvt = '101' ) ).
    cl_abap_unit_assert=>assert_not_initial( act = posting( material = 'Marine' ) ).
    cl_abap_unit_assert=>assert_not_initial( act = posting( quantity = 0 minerals = 0 ) msg = 'nothing posted for nothing' ).
    cl_abap_unit_assert=>assert_not_initial( act = posting( quantity = -5 minerals = -5 ) ).
    cl_abap_unit_assert=>assert_not_initial( act = posting( minerals = 6 ) msg = 'value and quantity differ' ).
    cl_abap_unit_assert=>assert_not_initial( act = posting( gas = 1 ) msg = 'minerals carry no gas value' ).
    cl_abap_unit_assert=>assert_not_initial( act = posting( material = 'VESPENE' quantity = 3 minerals = 3 gas = 0 ) ).
    cl_abap_unit_assert=>assert_not_initial( act = posting( plant = 'A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1' ) ).
    cl_abap_unit_assert=>assert_not_initial( act = posting( source = 'REPLAY' ) ).
    cl_abap_unit_assert=>assert_not_initial( act = posting( source = '' ) ).
  ENDMETHOD.
ENDCLASS.

CLASS ltc_pm DEFINITION FINAL FOR TESTING
  DURATION SHORT RISK LEVEL HARMLESS.
  PRIVATE SECTION.
    CONSTANTS game        TYPE sysuuid_x16 VALUE 'AE000000000000000000000000000001'.
    CONSTANTS division    TYPE sysuuid_x16 VALUE 'AE000000000000000000000000000002'.
    CONSTANTS rival       TYPE sysuuid_x16 VALUE 'AE000000000000000000000000000003'.
    CONSTANTS plant       TYPE sysuuid_x16 VALUE 'AE000000000000000000000000000004'.
    CONSTANTS rival_plant TYPE sysuuid_x16 VALUE 'AE000000000000000000000000000005'.
    CONSTANTS notif       TYPE sysuuid_x16 VALUE 'AE000000000000000000000000000006'.
    CONSTANTS notif2      TYPE sysuuid_x16 VALUE 'AE000000000000000000000000000007'.
    CONSTANTS barracks    TYPE zsce_event-unit_tag VALUE 5001.
    CONSTANTS depot       TYPE zsce_event-unit_tag VALUE 5002.
    CONSTANTS ruin        TYPE zsce_event-unit_tag VALUE 5003.
    CONSTANTS rival_depot TYPE zsce_event-unit_tag VALUE 5004.
    CONSTANTS scv         TYPE zsce_event-unit_tag VALUE 6001.
    CONSTANTS dead_scv    TYPE zsce_event-unit_tag VALUE 6002.
    CONSTANTS rival_scv   TYPE zsce_event-unit_tag VALUE 6003.
    CONSTANTS marine      TYPE zsce_event-unit_tag VALUE 6004.
    CLASS-DATA sql TYPE REF TO if_osql_test_environment.
    DATA events TYPE STANDARD TABLE OF zsce_event WITH EMPTY KEY.
    CLASS-METHODS class_setup.
    CLASS-METHODS class_teardown.
    METHODS setup.
    METHODS ledger IMPORTING of       TYPE sysuuid_x16 DEFAULT division
                             tag      TYPE zsce_event-unit_tag
                             mvt      TYPE zsce_event-mvt_type DEFAULT '101'
                             material TYPE zsce_event-matnr.
    "! a notification as the bot posts it; the failures of the MODIFY (the save checks come with the commit)
    METHODS open IMPORTING uuid          TYPE sysuuid_x16 DEFAULT notif
                           of            TYPE sysuuid_x16 DEFAULT division
                           tag           TYPE zsce_event-unit_tag DEFAULT barracks
                           material      TYPE zsce_event-matnr DEFAULT 'Barracks'
                           at            TYPE sysuuid_x16 OPTIONAL
                           priority      TYPE zsce_notif-priority DEFAULT '2'
                           health        TYPE i DEFAULT 500
                           healthmax     TYPE i DEFAULT 1000.
    "! Create Repair Order; the order's UUID, initial when refused
    METHODS release IMPORTING uuid         TYPE sysuuid_x16 DEFAULT notif
                    RETURNING VALUE(order) TYPE sysuuid_x16.
    "! reportRepair; the refusal, empty when accepted
    METHODS report IMPORTING order        TYPE sysuuid_x16
                             status       TYPE zsce_maintord-order_status
                             worker       TYPE zsce_event-unit_tag DEFAULT 0
                             started      TYPE i DEFAULT 0
                             at           TYPE i DEFAULT 0
                             text         TYPE zsce_maintord-status_text DEFAULT ''
                             outcome      TYPE zsce_notif-notif_status DEFAULT ''
                   RETURNING VALUE(error) TYPE string.
    "! reportNotification; the refusal, empty when accepted
    METHODS update IMPORTING uuid         TYPE sysuuid_x16 DEFAULT notif
                             status       TYPE zsce_notif-notif_status DEFAULT ''
                             priority     TYPE zsce_notif-priority DEFAULT '2'
                             health       TYPE i DEFAULT 500
                             healthmax    TYPE i DEFAULT 1000
                             at           TYPE i DEFAULT 0
                             text         TYPE zsce_notif-status_text DEFAULT ''
                   RETURNING VALUE(error) TYPE string.
    METHODS cancel IMPORTING order        TYPE sysuuid_x16
                   RETURNING VALUE(error) TYPE string.
    METHODS order_now IMPORTING uuid       TYPE sysuuid_x16
                      RETURNING VALUE(row) TYPE zi_scemaintorder.
    METHODS notification_now IMPORTING uuid       TYPE sysuuid_x16 DEFAULT notif
                             RETURNING VALUE(row) TYPE zi_scenotification.
    METHODS orders_of IMPORTING uuid         TYPE sysuuid_x16 DEFAULT notif
                      RETURNING VALUE(count) TYPE i.
    METHODS started_order RETURNING VALUE(order) TYPE sysuuid_x16.

    METHODS new_notification_is_open FOR TESTING RAISING cx_static_check.
    METHODS bad_notifications_are_refused FOR TESTING RAISING cx_static_check.
    METHODS one_open_per_equipment FOR TESTING RAISING cx_static_check.
    METHODS create_order_releases FOR TESTING RAISING cx_static_check.
    METHODS create_order_only_once FOR TESTING RAISING cx_static_check.
    METHODS no_order_for_a_ruin FOR TESTING RAISING cx_static_check.
    METHODS buttons_follow_the_status FOR TESTING RAISING cx_static_check.
    METHODS cancel_released_reopens FOR TESTING RAISING cx_static_check.
    METHODS cancel_started_is_requested FOR TESTING RAISING cx_static_check.
    METHODS repair_needs_a_live_scv FOR TESTING RAISING cx_static_check.
    METHODS confirmed_closes FOR TESTING RAISING cx_static_check.
    METHODS repeated_reports FOR TESTING RAISING cx_static_check.
    METHODS released_jumps_to_confirmed FOR TESTING RAISING cx_static_check.
    METHODS cancel_request_is_kept FOR TESTING RAISING cx_static_check.
    METHODS cancelled_names_the_outcome FOR TESTING RAISING cx_static_check.
    METHODS report_parameters_are_checked FOR TESTING RAISING cx_static_check.
    METHODS notification_is_updated FOR TESTING RAISING cx_static_check.
    METHODS close_takes_the_released_order FOR TESTING RAISING cx_static_check.
    METHODS close_waits_for_the_repair FOR TESTING RAISING cx_static_check.
    METHODS repair_cost_is_checked FOR TESTING RAISING cx_static_check.
    METHODS repair_cost_is_final FOR TESTING RAISING cx_static_check.
ENDCLASS.

CLASS ltc_pm IMPLEMENTATION.
  METHOD class_setup.
    sql = cl_osql_test_environment=>create(
            VALUE #( ( 'ZSCE_GAME' ) ( 'ZSCE_DIVISION' ) ( 'ZSCE_PLANT' ) ( 'ZSCE_PRODORD' ) ( 'ZSCE_EVENT' )
                     ( 'ZSCE_MATERIAL' ) ( 'ZSCE_NOTIF' ) ( 'ZSCE_MAINTORD' ) ) ).
  ENDMETHOD.

  METHOD class_teardown.
    sql->destroy( ).
  ENDMETHOD.

  METHOD ledger.
    APPEND VALUE #( event_uuid    = CONV sysuuid_x16( |EE{ lines( events ) + 1 WIDTH = 30 ALIGN = RIGHT PAD = '0' }| )
                    division_uuid = of
                    unit_tag      = tag
                    mvt_type      = mvt
                    matnr         = material
                    quantity      = 1
                    game_seconds  = 300
                    event_source  = 'LIVE' ) TO events.
  ENDMETHOD.

  METHOD setup.
    " two divisions with a plant each, created in the test's LUW (actions do not see rows of the doubles);
    " the ledger is read by SELECT and lives in the doubles
    DATA materials TYPE STANDARD TABLE OF zsce_material WITH EMPTY KEY.
    sql->clear_doubles( ).
    ROLLBACK ENTITIES.
    materials = VALUE #( bukrs = '1000'
      ( material_uuid = 'AE0000000000000000000000000000A1' matnr = 'Barracks' category = 'STRUCTURE' )
      ( material_uuid = 'AE0000000000000000000000000000A2' matnr = 'SupplyDepot' category = 'STRUCTURE' )
      ( material_uuid = 'AE0000000000000000000000000000A3' matnr = 'SCV' category = 'UNIT' )
      ( material_uuid = 'AE0000000000000000000000000000A4' matnr = 'Marine' category = 'UNIT' ) ).
    sql->insert_test_data( materials ).
    CLEAR events.
    ledger( tag = barracks material = 'Barracks' ).
    ledger( tag = depot material = 'SupplyDepot' ).
    ledger( tag = ruin material = 'Barracks' ).
    ledger( tag = ruin material = 'Barracks' mvt = '551' ).
    ledger( tag = scv material = 'SCV' mvt = '561' ).
    ledger( tag = dead_scv material = 'SCV' mvt = '561' ).
    ledger( tag = dead_scv material = 'SCV' mvt = '551' ).
    ledger( tag = marine material = 'Marine' ).
    ledger( of = rival tag = rival_depot material = 'SupplyDepot' ).
    ledger( of = rival tag = rival_scv material = 'SCV' mvt = '561' ).
    sql->insert_test_data( events ).
    MODIFY ENTITIES OF zi_scegame
      ENTITY game
        CREATE FIELDS ( gameuuid replayhash )
        WITH VALUE #( ( %cid = 'g1' gameuuid = game replayhash = 'PM' ) )
        CREATE BY \_division FIELDS ( divisionuuid companycode divisioncode )
        WITH VALUE #( ( %cid_ref = 'g1'
                        %target  = VALUE #( ( %cid = 'd1' divisionuuid = division companycode = '1000' divisioncode = 'LIVE' )
                                            ( %cid = 'd2' divisionuuid = rival companycode = '1000' divisioncode = 'P2' ) ) ) )
      ENTITY division
        CREATE BY \_plant FIELDS ( plantuuid plantcode )
        WITH VALUE #( ( %cid_ref = 'd1' %target = VALUE #( ( %cid = 'p1' plantuuid = plant plantcode = '0001' ) ) )
                      ( %cid_ref = 'd2' %target = VALUE #( ( %cid = 'p2' plantuuid = rival_plant plantcode = '0001' ) ) ) )
      FAILED DATA(failed).
    cl_abap_unit_assert=>assert_initial( act = failed msg = 'seed must be accepted' ).
  ENDMETHOD.

  METHOD open.
    MODIFY ENTITIES OF zi_scegame
      ENTITY division
        CREATE BY \_notification
          FIELDS ( notificationuuid unittag material plantuuid priority health healthmax reportedat statustext )
          WITH VALUE #( ( divisionuuid = of
                          %target = VALUE #( ( %cid = |N{ uuid }| notificationuuid = uuid unittag = tag material = material
                                               plantuuid = at priority = priority health = health healthmax = healthmax
                                               reportedat = 280 statustext = 'damaged' ) ) ) )
      FAILED DATA(failed).
    cl_abap_unit_assert=>assert_initial( act = failed msg = 'the checks of a notification run on save' ).
  ENDMETHOD.

  METHOD release.
    MODIFY ENTITIES OF zi_scegame
      ENTITY notification
        EXECUTE createorder FROM VALUE #( ( notificationuuid = uuid ) )
      FAILED DATA(failed).
    IF failed-notification IS NOT INITIAL.
      RETURN.
    ENDIF.
    READ ENTITIES OF zi_scegame
      ENTITY notification
        FIELDS ( divisionuuid ) WITH VALUE #( ( notificationuuid = uuid ) )
      RESULT DATA(notifications).
    READ ENTITIES OF zi_scegame
      ENTITY division BY \_maintorder
        ALL FIELDS WITH VALUE #( ( divisionuuid = notifications[ 1 ]-divisionuuid ) )
      RESULT DATA(orders).
    LOOP AT orders INTO DATA(row) WHERE notificationuuid = uuid AND orderstatus = 'RELEASED'.
      order = row-orderuuid.
    ENDLOOP.
  ENDMETHOD.

  METHOD report.
    MODIFY ENTITIES OF zi_scegame
      ENTITY maintorder
        EXECUTE reportrepair
          FROM VALUE #( ( orderuuid = order
                          %param    = VALUE #( orderstatus = status workertag = worker startedat = started atseconds = at
                                               statustext = text notificationoutcome = outcome ) ) )
      FAILED DATA(failed) REPORTED DATA(reported).
    IF failed-maintorder IS NOT INITIAL.
      error = COND #( WHEN reported-maintorder IS INITIAL THEN `refused`
                      ELSE reported-maintorder[ 1 ]-%msg->if_message~get_text( ) ).
    ENDIF.
  ENDMETHOD.

  METHOD update.
    MODIFY ENTITIES OF zi_scegame
      ENTITY notification
        EXECUTE reportnotification
          FROM VALUE #( ( notificationuuid = uuid
                          %param           = VALUE #( notificationstatus = status priority = priority health = health
                                                      healthmax = healthmax atseconds = at statustext = text ) ) )
      FAILED DATA(failed) REPORTED DATA(reported).
    IF failed-notification IS NOT INITIAL.
      error = COND #( WHEN reported-notification IS INITIAL THEN `refused`
                      ELSE reported-notification[ 1 ]-%msg->if_message~get_text( ) ).
    ENDIF.
  ENDMETHOD.

  METHOD cancel.
    MODIFY ENTITIES OF zi_scegame
      ENTITY maintorder
        EXECUTE cancelorder FROM VALUE #( ( orderuuid = order ) )
      FAILED DATA(failed) REPORTED DATA(reported).
    IF failed-maintorder IS NOT INITIAL.
      error = COND #( WHEN reported-maintorder IS INITIAL THEN `refused`
                      ELSE reported-maintorder[ 1 ]-%msg->if_message~get_text( ) ).
    ENDIF.
  ENDMETHOD.

  METHOD order_now.
    READ ENTITIES OF zi_scegame
      ENTITY maintorder
        ALL FIELDS WITH VALUE #( ( orderuuid = uuid ) )
      RESULT DATA(rows).
    row = CORRESPONDING #( VALUE #( rows[ 1 ] OPTIONAL ) ).
  ENDMETHOD.

  METHOD notification_now.
    READ ENTITIES OF zi_scegame
      ENTITY notification
        ALL FIELDS WITH VALUE #( ( notificationuuid = uuid ) )
      RESULT DATA(rows).
    row = CORRESPONDING #( VALUE #( rows[ 1 ] OPTIONAL ) ).
  ENDMETHOD.

  METHOD orders_of.
    READ ENTITIES OF zi_scegame
      ENTITY division BY \_maintorder
        FIELDS ( notificationuuid ) WITH VALUE #( ( divisionuuid = division ) )
      RESULT DATA(orders).
    count = REDUCE #( INIT n = 0 FOR o IN orders WHERE ( notificationuuid = uuid ) NEXT n = n + 1 ).
  ENDMETHOD.

  METHOD started_order.
    open( ).
    order = release( ).
    cl_abap_unit_assert=>assert_not_initial( act = order msg = 'an order to work on' ).
    cl_abap_unit_assert=>assert_initial( act = report( order = order status = 'STARTED' worker = scv started = 310 text = 'SCV on its way' ) ).
  ENDMETHOD.

  METHOD new_notification_is_open.
    open( at = plant ).
    COMMIT ENTITIES RESPONSE OF zi_scegame FAILED DATA(commit_failed) REPORTED DATA(commit_reported).
    cl_abap_unit_assert=>assert_initial( act = commit_failed msg = 'a damaged Barracks of the division' ).
    SELECT SINGLE * FROM zsce_notif WHERE notif_uuid = @notif INTO @DATA(saved).
    cl_abap_unit_assert=>assert_equals( act = saved-notif_status exp = 'OPEN' msg = 'nobody sent a status' ).
    cl_abap_unit_assert=>assert_equals( act = saved-division_uuid exp = division ).
    cl_abap_unit_assert=>assert_equals( act = saved-unit_tag exp = barracks ).
    cl_abap_unit_assert=>assert_equals( act = saved-health exp = 500 ).
    cl_abap_unit_assert=>assert_equals( act = saved-closed_at exp = 0 ).
  ENDMETHOD.

  METHOD bad_notifications_are_refused.
    " all in one request: the save refuses each bad one by its key and accepts none
    open( uuid = 'AE0000000000000000000000000000B0' tag = depot material = 'SupplyDepot' ).                " good
    open( uuid = 'AE0000000000000000000000000000B1' tag = 0 ).
    open( uuid = 'AE0000000000000000000000000000B2' tag = barracks health = 1001 ).
    open( uuid = 'AE0000000000000000000000000000B3' tag = barracks priority = '9' ).
    open( uuid = 'AE0000000000000000000000000000B4' tag = 5999 ).                                          " no receipt
    open( uuid = 'AE0000000000000000000000000000B5' tag = ruin ).                                          " destroyed
    open( uuid = 'AE0000000000000000000000000000B6' tag = marine material = 'Marine' ).                    " no structure
    open( uuid = 'AE0000000000000000000000000000B7' tag = barracks material = 'SupplyDepot' ).             " another material
    open( uuid = 'AE0000000000000000000000000000B8' tag = rival_depot material = 'SupplyDepot' ).          " another division's
    open( uuid = 'AE0000000000000000000000000000B9' tag = barracks at = rival_plant ).                     " another division's plant
    COMMIT ENTITIES RESPONSE OF zi_scegame FAILED DATA(commit_failed) REPORTED DATA(commit_reported).

    DO 9 TIMES.
      DATA(bad) = CONV sysuuid_x16( |AE0000000000000000000000000000B{ sy-index }| ).
      cl_abap_unit_assert=>assert_true( act = xsdbool( line_exists( commit_failed-notification[ notificationuuid = bad ] ) )
                                        msg = |B{ sy-index } must be refused| ).
    ENDDO.
    cl_abap_unit_assert=>assert_false(
      act = xsdbool( line_exists( commit_failed-notification[ notificationuuid = 'AE0000000000000000000000000000B0' ] ) )
      msg = 'the good one is not the reason' ).
    DATA(texts) = VALUE string_table( FOR r IN commit_reported-notification ( r-%msg->if_message~get_text( ) ) ).
    cl_abap_unit_assert=>assert_table_contains( line = `Equipment 5999 unknown` table = texts ).
    cl_abap_unit_assert=>assert_table_contains( line = `Equipment 5003 destroyed` table = texts ).
    cl_abap_unit_assert=>assert_table_contains( line = `Equipment 5004 unknown` table = texts msg = 'a tag of another division' ).
    cl_abap_unit_assert=>assert_table_contains( line = `Marine is no structure here` table = texts ).
    cl_abap_unit_assert=>assert_table_contains( line = `Plant of another division` table = texts ).
    SELECT COUNT( * ) FROM zsce_notif INTO @DATA(saved).
    cl_abap_unit_assert=>assert_equals( act = saved exp = 0 ).
  ENDMETHOD.

  METHOD one_open_per_equipment.
    " both in one request: neither is persisted yet, the check must see the transactional rows
    open( uuid = notif ).
    open( uuid = notif2 ).
    COMMIT ENTITIES RESPONSE OF zi_scegame FAILED DATA(commit_failed) REPORTED DATA(commit_reported).
    cl_abap_unit_assert=>assert_equals( act = lines( commit_failed-notification ) exp = 2 ).
    cl_abap_unit_assert=>assert_equals( act = commit_reported-notification[ 1 ]-%msg->if_message~get_text( )
                                        exp = `Open notification exists` ).
  ENDMETHOD.

  METHOD create_order_releases.
    open( at = plant priority = '1' health = 300 ).
    DATA(order) = release( ).
    COMMIT ENTITIES RESPONSE OF zi_scegame FAILED DATA(commit_failed) REPORTED DATA(commit_reported).

    cl_abap_unit_assert=>assert_not_initial( act = order ).
    cl_abap_unit_assert=>assert_initial( act = commit_failed ).
    SELECT SINGLE * FROM zsce_maintord WHERE order_uuid = @order INTO @DATA(saved).
    cl_abap_unit_assert=>assert_equals( act = saved-order_status exp = 'RELEASED' ).
    cl_abap_unit_assert=>assert_equals( act = saved-division_uuid exp = division ).
    cl_abap_unit_assert=>assert_equals( act = saved-notif_uuid exp = notif ).
    cl_abap_unit_assert=>assert_equals( act = saved-unit_tag exp = barracks ).
    cl_abap_unit_assert=>assert_equals( act = saved-matnr exp = 'Barracks' ).
    cl_abap_unit_assert=>assert_equals( act = saved-plant_uuid exp = plant ).
    cl_abap_unit_assert=>assert_equals( act = saved-priority exp = '1' ).
    cl_abap_unit_assert=>assert_equals( act = saved-reported_at exp = 280 ).
    cl_abap_unit_assert=>assert_equals( act = saved-released_at exp = 300 msg = 'the division''s game clock' ).
    SELECT SINGLE notif_status FROM zsce_notif WHERE notif_uuid = @notif INTO @DATA(status).
    cl_abap_unit_assert=>assert_equals( act = status exp = 'IN_PROCESS' ).
  ENDMETHOD.

  METHOD create_order_only_once.
    " RAP itself refuses the same key twice in one call (BEHAVIOR_CONTRACT_VIOLATION), so the repetition that can
    " reach the handler is a second call in the same transaction
    open( ).
    cl_abap_unit_assert=>assert_not_initial( act = release( ) ).
    MODIFY ENTITIES OF zi_scegame
      ENTITY notification
        EXECUTE createorder FROM VALUE #( ( notificationuuid = notif ) )
      FAILED DATA(again) REPORTED DATA(reported).
    " feature control answers first (IN_PROCESS offers no order); the handler's own check is the second line
    cl_abap_unit_assert=>assert_equals( act = lines( again-notification ) exp = 1 msg = 'the second call is refused' ).
    cl_abap_unit_assert=>assert_equals( act = orders_of( ) exp = 1 ).
    COMMIT ENTITIES RESPONSE OF zi_scegame FAILED DATA(commit_failed) REPORTED DATA(commit_reported).
    cl_abap_unit_assert=>assert_initial( act = commit_failed ).
    SELECT COUNT( * ) FROM zsce_maintord WHERE notif_uuid = @notif INTO @DATA(saved).
    cl_abap_unit_assert=>assert_equals( act = saved exp = 1 ).
  ENDMETHOD.

  METHOD no_order_for_a_ruin.
    DATA lost TYPE STANDARD TABLE OF zsce_event WITH EMPTY KEY.
    open( ).
    " destroyed after the notification, before the click
    lost = VALUE #( ( event_uuid = 'EE0000000000000000000000000000FF' division_uuid = division unit_tag = barracks
                      mvt_type = '551' matnr = 'Barracks' quantity = 1 game_seconds = 320 ) ).
    sql->insert_test_data( lost ).
    cl_abap_unit_assert=>assert_initial( act = release( ) ).
    cl_abap_unit_assert=>assert_equals( act = orders_of( ) exp = 0 ).
    cl_abap_unit_assert=>assert_equals( act = notification_now( )-notificationstatus exp = 'OPEN' ).
  ENDMETHOD.

  METHOD buttons_follow_the_status.
    DATA(order) = started_order( ).
    open( uuid = notif2 tag = depot material = 'SupplyDepot' ).
    DATA(waiting) = release( notif2 ).
    cl_abap_unit_assert=>assert_initial( act = report( order = order status = 'CONFIRMED' worker = scv started = 310 at = 400 ) ).

    GET PERMISSIONS ONLY INSTANCE FEATURES ENTITY zi_scemaintorder
      FROM VALUE #( ( orderuuid = order ) ( orderuuid = waiting ) )
      REQUEST VALUE #( %action-cancelorder = if_abap_behv=>mk-on )
      RESULT DATA(orders).
    " GET PERMISSIONS answers only restricted instances
    cl_abap_unit_assert=>assert_equals( act = lines( orders-instances ) exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = orders-instances[ 1 ]-orderuuid exp = order msg = 'a repaired order cannot be cancelled' ).

    GET PERMISSIONS ONLY INSTANCE FEATURES ENTITY zi_scenotification
      FROM VALUE #( ( notificationuuid = notif ) ( notificationuuid = notif2 ) )
      REQUEST VALUE #( %action-createorder = if_abap_behv=>mk-on )
      RESULT DATA(notifications).
    cl_abap_unit_assert=>assert_equals( act = lines( notifications-instances ) exp = 2 msg = 'CLOSED and IN_PROCESS offer no order' ).
  ENDMETHOD.

  METHOD cancel_released_reopens.
    open( ).
    DATA(order) = release( ).
    cl_abap_unit_assert=>assert_initial( act = cancel( order ) ).
    cl_abap_unit_assert=>assert_equals( act = order_now( order )-orderstatus exp = 'CANCELLED' ).
    cl_abap_unit_assert=>assert_equals( act = order_now( order )-statustext exp = 'cancelled in SAP' ).
    cl_abap_unit_assert=>assert_equals( act = notification_now( )-notificationstatus exp = 'OPEN' ).
    cl_abap_unit_assert=>assert_not_initial( act = cancel( order ) msg = 'twice in one transaction' ).
    cl_abap_unit_assert=>assert_not_initial( act = release( ) msg = 'the notification takes a new order' ).
    cl_abap_unit_assert=>assert_equals( act = orders_of( ) exp = 2 ).
  ENDMETHOD.

  METHOD cancel_started_is_requested.
    DATA(order) = started_order( ).
    cl_abap_unit_assert=>assert_initial( act = cancel( order ) ).
    cl_abap_unit_assert=>assert_equals( act = order_now( order )-orderstatus exp = 'CANCELLING' ).
    cl_abap_unit_assert=>assert_equals( act = order_now( order )-statustext exp = 'cancel requested' ).
    cl_abap_unit_assert=>assert_equals( act = notification_now( )-notificationstatus exp = 'IN_PROCESS' ).
    cl_abap_unit_assert=>assert_not_initial( act = cancel( order ) msg = 'a second request is refused' ).
  ENDMETHOD.

  METHOD repair_needs_a_live_scv.
    open( ).
    DATA(order) = release( ).
    cl_abap_unit_assert=>assert_equals( act = report( order = order status = 'STARTED' ) exp = `STARTED needs the SCV tag` ).
    cl_abap_unit_assert=>assert_equals( act = report( order = order status = 'STARTED' worker = dead_scv )
                                        exp = `SCV 6002 destroyed` ).
    cl_abap_unit_assert=>assert_equals( act = report( order = order status = 'STARTED' worker = rival_scv )
                                        exp = `SCV 6003 unknown` msg = 'an SCV of another division' ).
    cl_abap_unit_assert=>assert_equals( act = report( order = order status = 'STARTED' worker = marine )
                                        exp = `SCV 6004 unknown` msg = 'a Marine repairs nothing' ).
    cl_abap_unit_assert=>assert_equals( act = order_now( order )-orderstatus exp = 'RELEASED' ).
    cl_abap_unit_assert=>assert_initial( act = report( order = order status = 'STARTED' worker = scv started = 310
                                                       text = 'SCV on its way' ) ).
    DATA(row) = order_now( order ).
    cl_abap_unit_assert=>assert_equals( act = row-orderstatus exp = 'STARTED' ).
    cl_abap_unit_assert=>assert_equals( act = row-workertag exp = scv ).
    cl_abap_unit_assert=>assert_equals( act = row-startedat exp = 310 ).
    cl_abap_unit_assert=>assert_equals( act = notification_now( )-notificationstatus exp = 'IN_PROCESS' ).
  ENDMETHOD.

  METHOD confirmed_closes.
    DATA(order) = started_order( ).
    cl_abap_unit_assert=>assert_initial( act = report( order = order status = 'CONFIRMED' worker = scv started = 310 at = 400
                                                       text = 'repaired' ) ).
    COMMIT ENTITIES RESPONSE OF zi_scegame FAILED DATA(commit_failed) REPORTED DATA(commit_reported).
    cl_abap_unit_assert=>assert_initial( act = commit_failed ).
    SELECT SINGLE * FROM zsce_maintord WHERE order_uuid = @order INTO @DATA(saved).
    cl_abap_unit_assert=>assert_equals( act = saved-order_status exp = 'CONFIRMED' ).
    cl_abap_unit_assert=>assert_equals( act = saved-confirmed_at exp = 400 ).
    cl_abap_unit_assert=>assert_equals( act = saved-worker_tag exp = scv ).
    SELECT SINGLE * FROM zsce_notif WHERE notif_uuid = @notif INTO @DATA(closed).
    cl_abap_unit_assert=>assert_equals( act = closed-notif_status exp = 'CLOSED' msg = 'in the same transaction' ).
    cl_abap_unit_assert=>assert_equals( act = closed-closed_at exp = 400 ).
    cl_abap_unit_assert=>assert_equals( act = closed-status_text exp = 'repaired' ).
  ENDMETHOD.

  METHOD repeated_reports.
    DATA(order) = started_order( ).
    " the same status again: the progress text may change
    cl_abap_unit_assert=>assert_initial( act = report( order = order status = 'STARTED' worker = scv started = 310 text = 'repairing' ) ).
    cl_abap_unit_assert=>assert_equals( act = order_now( order )-statustext exp = 'repairing' ).
    cl_abap_unit_assert=>assert_equals( act = order_now( order )-orderstatus exp = 'STARTED' ).
    cl_abap_unit_assert=>assert_initial( act = report( order = order status = 'CONFIRMED' worker = scv started = 310 at = 400
                                                       text = 'repaired' ) ).
    " a finished order reported again succeeds and changes nothing
    cl_abap_unit_assert=>assert_initial( act = report( order = order status = 'CONFIRMED' worker = scv started = 310 at = 999
                                                       text = 'late copy' ) ).
    cl_abap_unit_assert=>assert_equals( act = order_now( order )-confirmedat exp = 400 ).
    cl_abap_unit_assert=>assert_equals( act = order_now( order )-statustext exp = 'repaired' ).
    " a stale report must not take it back
    cl_abap_unit_assert=>assert_equals( act = report( order = order status = 'STARTED' worker = scv started = 310 )
                                        exp = `Order already CONFIRMED` ).
    cl_abap_unit_assert=>assert_equals( act = report( order = order status = 'RELEASED' text = 'interrupted' )
                                        exp = `Order already CONFIRMED` ).
    cl_abap_unit_assert=>assert_equals( act = report( order = order status = 'CANCELLED' outcome = 'OPEN' )
                                        exp = `Order already CONFIRMED` ).
    cl_abap_unit_assert=>assert_equals( act = order_now( order )-orderstatus exp = 'CONFIRMED' ).
    cl_abap_unit_assert=>assert_equals( act = notification_now( )-notificationstatus exp = 'CLOSED' msg = 'and stays closed' ).
  ENDMETHOD.

  METHOD released_jumps_to_confirmed.
    " the STARTED report never arrived: the confirmation carries everything
    open( ).
    DATA(order) = release( ).
    cl_abap_unit_assert=>assert_initial( act = report( order = order status = 'CONFIRMED' worker = scv started = 310 at = 400
                                                       text = 'repaired' outcome = 'CLOSED' ) ).
    DATA(row) = order_now( order ).
    cl_abap_unit_assert=>assert_equals( act = row-orderstatus exp = 'CONFIRMED' ).
    cl_abap_unit_assert=>assert_equals( act = row-workertag exp = scv ).
    cl_abap_unit_assert=>assert_equals( act = row-startedat exp = 310 ).
    cl_abap_unit_assert=>assert_equals( act = row-confirmedat exp = 400 ).
    cl_abap_unit_assert=>assert_equals( act = notification_now( )-notificationstatus exp = 'CLOSED' ).
  ENDMETHOD.

  METHOD cancel_request_is_kept.
    DATA(order) = started_order( ).
    cl_abap_unit_assert=>assert_initial( act = cancel( order ) ).
    " an interruption or a late STARTED must not wipe the cancel request
    cl_abap_unit_assert=>assert_equals( act = report( order = order status = 'RELEASED' text = 'interrupted: SCV lost' )
                                        exp = `Cancel requested: RELEASED refused` ).
    cl_abap_unit_assert=>assert_equals( act = report( order = order status = 'STARTED' worker = scv started = 310 )
                                        exp = `Cancel requested: STARTED refused` ).
    cl_abap_unit_assert=>assert_equals( act = order_now( order )-orderstatus exp = 'CANCELLING' ).
    cl_abap_unit_assert=>assert_initial( act = report( order = order status = 'CANCELLED' worker = scv started = 310 at = 350
                                                       text = 'cancelled in game' outcome = 'OPEN' ) ).
    cl_abap_unit_assert=>assert_equals( act = order_now( order )-orderstatus exp = 'CANCELLED' ).
    cl_abap_unit_assert=>assert_equals( act = notification_now( )-notificationstatus exp = 'OPEN' msg = 'the damage is still there' ).
    cl_abap_unit_assert=>assert_initial( act = notification_now( )-closedat ).

    " the repair was done before the request arrived: the fact wins
    open( uuid = notif2 tag = depot material = 'SupplyDepot' ).
    DATA(second) = release( notif2 ).
    cl_abap_unit_assert=>assert_initial( act = report( order = second status = 'STARTED' worker = scv started = 360 ) ).
    cl_abap_unit_assert=>assert_initial( act = cancel( second ) ).
    cl_abap_unit_assert=>assert_initial( act = report( order = second status = 'CONFIRMED' worker = scv started = 360 at = 380
                                                       text = 'cannot cancel: already repaired' ) ).
    cl_abap_unit_assert=>assert_equals( act = order_now( second )-orderstatus exp = 'CONFIRMED' ).
    cl_abap_unit_assert=>assert_equals( act = notification_now( notif2 )-notificationstatus exp = 'CLOSED' ).
  ENDMETHOD.

  METHOD cancelled_names_the_outcome.
    DATA(order) = started_order( ).
    cl_abap_unit_assert=>assert_not_initial( act = report( order = order status = 'CANCELLED' text = 'equipment destroyed' )
                                             msg = 'OPEN or CLOSED must be said' ).
    cl_abap_unit_assert=>assert_not_initial( act = report( order = order status = 'CANCELLED' outcome = 'IN_PROCESS' ) ).
    cl_abap_unit_assert=>assert_not_initial( act = report( order = order status = 'STARTED' worker = scv outcome = 'CLOSED' ) ).
    cl_abap_unit_assert=>assert_not_initial( act = report( order = order status = 'CONFIRMED' worker = scv at = 400 outcome = 'OPEN' ) ).
    cl_abap_unit_assert=>assert_equals( act = order_now( order )-orderstatus exp = 'STARTED' ).
    " the equipment died under repair; its SCV may be dead as well by now
    cl_abap_unit_assert=>assert_initial( act = report( order = order status = 'CANCELLED' worker = dead_scv started = 310 at = 330
                                                       text = 'equipment destroyed' outcome = 'CLOSED' ) ).
    cl_abap_unit_assert=>assert_equals( act = order_now( order )-orderstatus exp = 'CANCELLED' ).
    cl_abap_unit_assert=>assert_initial( act = order_now( order )-confirmedat ).
    DATA(closed) = notification_now( ).
    cl_abap_unit_assert=>assert_equals( act = closed-notificationstatus exp = 'CLOSED' ).
    cl_abap_unit_assert=>assert_equals( act = closed-closedat exp = 330 ).
    cl_abap_unit_assert=>assert_equals( act = closed-statustext exp = 'equipment destroyed' ).
  ENDMETHOD.

  METHOD report_parameters_are_checked.
    DATA(order) = started_order( ).
    cl_abap_unit_assert=>assert_not_initial( act = report( order = order status = 'CANCELLING' ) msg = 'SAP''s own status' ).
    cl_abap_unit_assert=>assert_not_initial( act = report( order = order status = 'SCRAPPED' ) ).
    cl_abap_unit_assert=>assert_not_initial( act = report( order = order status = '' ) ).
    cl_abap_unit_assert=>assert_not_initial( act = report( order = order status = 'CONFIRMED' worker = scv started = 310 at = -1 ) ).
    cl_abap_unit_assert=>assert_not_initial( act = report( order = order status = 'CONFIRMED' worker = -1 started = 310 at = 400 ) ).
    cl_abap_unit_assert=>assert_equals( act = report( order = order status = 'CONFIRMED' worker = scv started = 310 at = 300 )
                                        exp = `Confirmed before started` ).
    cl_abap_unit_assert=>assert_equals( act = report( order = order status = 'CONFIRMED' worker = rival_scv started = 310 at = 400 )
                                        exp = `SCV 6003 unknown` ).
    cl_abap_unit_assert=>assert_not_initial( act = report( order = 'AE0000000000000000000000000000FF' status = 'STARTED' worker = scv )
                                             msg = 'an order that does not exist' ).
    cl_abap_unit_assert=>assert_equals( act = order_now( order )-orderstatus exp = 'STARTED' ).
  ENDMETHOD.

  METHOD notification_is_updated.
    open( ).
    cl_abap_unit_assert=>assert_initial( act = update( priority = '1' health = 250 text = 'burning' ) ).
    DATA(row) = notification_now( ).
    cl_abap_unit_assert=>assert_equals( act = row-priority exp = '1' ).
    cl_abap_unit_assert=>assert_equals( act = row-health exp = 250 ).
    cl_abap_unit_assert=>assert_equals( act = row-statustext exp = 'burning' ).
    cl_abap_unit_assert=>assert_equals( act = row-notificationstatus exp = 'OPEN' ).
    cl_abap_unit_assert=>assert_not_initial( act = update( priority = '7' ) ).
    cl_abap_unit_assert=>assert_not_initial( act = update( health = 1001 ) ).
    cl_abap_unit_assert=>assert_not_initial( act = update( at = -1 ) ).
    cl_abap_unit_assert=>assert_not_initial( act = update( status = 'IN_PROCESS' ) msg = 'createOrder alone' ).
    cl_abap_unit_assert=>assert_not_initial( act = update( status = 'OPEN' ) ).
    cl_abap_unit_assert=>assert_equals( act = notification_now( )-health exp = 250 ).
    " an order does not change who may update
    cl_abap_unit_assert=>assert_not_initial( act = release( ) ).
    cl_abap_unit_assert=>assert_initial( act = update( priority = '1' health = 200 ) ).
    cl_abap_unit_assert=>assert_equals( act = notification_now( )-notificationstatus exp = 'IN_PROCESS' ).
  ENDMETHOD.

  METHOD close_takes_the_released_order.
    " Create Repair Order was clicked a moment before the bot's close arrives
    open( ).
    DATA(order) = release( ).
    cl_abap_unit_assert=>assert_initial( act = update( status = 'CLOSED' health = 0 at = 333 text = 'equipment destroyed' ) ).
    cl_abap_unit_assert=>assert_equals( act = order_now( order )-orderstatus exp = 'CANCELLED' msg = 'no released order is left behind' ).
    cl_abap_unit_assert=>assert_equals( act = order_now( order )-statustext exp = 'equipment destroyed' ).
    DATA(closed) = notification_now( ).
    cl_abap_unit_assert=>assert_equals( act = closed-notificationstatus exp = 'CLOSED' ).
    cl_abap_unit_assert=>assert_equals( act = closed-closedat exp = 333 ).
    " the bot's own view was stale: its report on that order is refused and tells it so
    cl_abap_unit_assert=>assert_equals( act = report( order = order status = 'STARTED' worker = scv started = 340 )
                                        exp = `Order already CANCELLED` ).
    " the close again succeeds and changes nothing; nothing reopens
    cl_abap_unit_assert=>assert_initial( act = update( status = 'CLOSED' health = 0 at = 999 text = 'late copy' ) ).
    cl_abap_unit_assert=>assert_equals( act = notification_now( )-closedat exp = 333 ).
    cl_abap_unit_assert=>assert_equals( act = update( health = 400 text = 'late health' ) exp = `Notification already CLOSED` ).
    cl_abap_unit_assert=>assert_initial( act = release( ) msg = 'no order for a closed notification' ).
    COMMIT ENTITIES RESPONSE OF zi_scegame FAILED DATA(commit_failed) REPORTED DATA(commit_reported).
    cl_abap_unit_assert=>assert_initial( act = commit_failed ).
    " closed: the equipment may be notified again
    SELECT COUNT( * ) FROM zsce_notif WHERE notif_status = 'CLOSED' INTO @DATA(saved).
    cl_abap_unit_assert=>assert_equals( act = saved exp = 1 ).
  ENDMETHOD.

  METHOD close_waits_for_the_repair.
    DATA(order) = started_order( ).
    cl_abap_unit_assert=>assert_equals( act = update( status = 'CLOSED' at = 333 text = 'no damage found' )
                                        exp = `Repair in work: report the repair` ).
    cl_abap_unit_assert=>assert_equals( act = notification_now( )-notificationstatus exp = 'IN_PROCESS' ).
    cl_abap_unit_assert=>assert_equals( act = order_now( order )-orderstatus exp = 'STARTED' ).
    " a new notification for the same equipment once the first is closed, in the same transaction
    cl_abap_unit_assert=>assert_initial( act = report( order = order status = 'CONFIRMED' worker = scv started = 310 at = 400 ) ).
    open( uuid = notif2 ).
    COMMIT ENTITIES RESPONSE OF zi_scegame FAILED DATA(commit_failed) REPORTED DATA(commit_reported).
    cl_abap_unit_assert=>assert_initial( act = commit_failed msg = 'new damage after a close is a new notification' ).
  ENDMETHOD.

  METHOD repair_cost_is_checked.
    DATA orders TYPE STANDARD TABLE OF zsce_maintord WITH EMPTY KEY.
    " persisted maintenance orders: one of the division, one of the rival
    orders = VALUE #( ( order_uuid = 'AE0000000000000000000000000000C1' division_uuid = division order_status = 'STARTED' )
                      ( order_uuid = 'AE0000000000000000000000000000C2' division_uuid = rival order_status = 'STARTED' ) ).
    sql->insert_test_data( orders ).
    MODIFY ENTITIES OF zi_scegame
      ENTITY division
        CREATE BY \_event
          FIELDS ( eventuuid orderuuid plantuuid movementtype material quantity mineralvalue gasvalue eventsource gameseconds )
          WITH VALUE #( ( divisionuuid = division
                          %target = VALUE #( gameseconds = 400
            ( %cid = 'e0' eventuuid = 'AE0000000000000000000000000000D0' orderuuid = 'AE0000000000000000000000000000C1' movementtype = '261'
              material = 'MINERAL' quantity = 13 mineralvalue = 13 gasvalue = 0 eventsource = 'LIVE' )
            ( %cid = 'e1' eventuuid = 'AE0000000000000000000000000000D1' orderuuid = 'AE0000000000000000000000000000C1' movementtype = '261'
              material = 'VESPENE' quantity = 13 mineralvalue = 0 gasvalue = 13 eventsource = 'LIVE' )
            ( %cid = 'e2' eventuuid = 'AE0000000000000000000000000000D2' orderuuid = 'AE0000000000000000000000000000C2' movementtype = '261'
              material = 'MINERAL' quantity = 13 mineralvalue = 13 gasvalue = 0 eventsource = 'LIVE' )
            ( %cid = 'e3' eventuuid = 'AE0000000000000000000000000000D3' orderuuid = 'AE0000000000000000000000000000C1' movementtype = '262'
              material = 'MINERAL' quantity = 13 mineralvalue = 13 gasvalue = 0 eventsource = 'LIVE' )
            ( %cid = 'e4' eventuuid = 'AE0000000000000000000000000000D4' orderuuid = 'AE0000000000000000000000000000C1' movementtype = '261'
              material = 'Barracks' quantity = 1 mineralvalue = 150 gasvalue = 0 eventsource = 'LIVE' )
            ( %cid = 'e5' eventuuid = 'AE0000000000000000000000000000D5' orderuuid = 'AE0000000000000000000000000000C1' movementtype = '261'
              material = 'MINERAL' quantity = 0 mineralvalue = 0 gasvalue = 0 eventsource = 'LIVE' )
            ( %cid = 'e6' eventuuid = 'AE0000000000000000000000000000D6' orderuuid = 'AE0000000000000000000000000000C1' movementtype = '261'
              material = 'MINERAL' quantity = 13 mineralvalue = 12 gasvalue = 0 eventsource = 'LIVE' )
            ( %cid = 'e7' eventuuid = 'AE0000000000000000000000000000D7' orderuuid = 'AE0000000000000000000000000000C1' movementtype = '261'
              material = 'MINERAL' quantity = 13 mineralvalue = 13 gasvalue = 0 eventsource = 'LIVE' plantuuid = plant )
            ( %cid = 'e8' eventuuid = 'AE0000000000000000000000000000D8' orderuuid = 'AE0000000000000000000000000000C1' movementtype = '261'
              material = 'MINERAL' quantity = 13 mineralvalue = 13 gasvalue = 0 eventsource = 'REPLAY' )
            " a production movement stays as free as it was
            ( %cid = 'e9' eventuuid = 'AE0000000000000000000000000000D9' orderuuid = 'AE0000000000000000000000000000CF'
              movementtype = '261' material = 'MINERAL' quantity = 50 mineralvalue = 50 eventsource = 'REPLAY'
              plantuuid = plant ) ) ) )
      FAILED DATA(failed).
    cl_abap_unit_assert=>assert_initial( act = failed ).
    COMMIT ENTITIES RESPONSE OF zi_scegame FAILED DATA(commit_failed) REPORTED DATA(commit_reported).

    DATA(refused) = VALUE string_table( FOR f IN commit_failed-event ( CONV string( f-eventuuid ) ) ).
    SORT refused.
    cl_abap_unit_assert=>assert_equals(
      act = refused
      exp = VALUE string_table( ( `AE0000000000000000000000000000D2` ) ( `AE0000000000000000000000000000D3` )
                                ( `AE0000000000000000000000000000D4` ) ( `AE0000000000000000000000000000D5` )
                                ( `AE0000000000000000000000000000D6` ) ( `AE0000000000000000000000000000D7` )
                                ( `AE0000000000000000000000000000D8` ) )
      msg = 'D0, D1 (repair cost) and D9 (production) are fine' ).
  ENDMETHOD.

  METHOD repair_cost_is_final.
    DATA orders TYPE STANDARD TABLE OF zsce_maintord WITH EMPTY KEY.
    orders = VALUE #( ( order_uuid = 'AE0000000000000000000000000000C1' division_uuid = division order_status = 'STARTED' ) ).
    sql->insert_test_data( orders ).
    MODIFY ENTITIES OF zi_scegame
      ENTITY division
        CREATE BY \_event
          FIELDS ( eventuuid orderuuid movementtype material quantity mineralvalue eventsource gameseconds )
          WITH VALUE #( ( divisionuuid = division
                          %target = VALUE #(
            eventsource = 'LIVE' movementtype = '261' gameseconds = 400 material = 'MINERAL' quantity = 13 mineralvalue = 13
            ( %cid = 'e0' eventuuid = 'AE0000000000000000000000000000D0' orderuuid = 'AE0000000000000000000000000000C1' )
            ( %cid = 'e1' eventuuid = 'AE0000000000000000000000000000D1' orderuuid = 'AE0000000000000000000000000000CF' ) ) ) )
      FAILED DATA(created).
    cl_abap_unit_assert=>assert_initial( act = created ).

    MODIFY ENTITIES OF zi_scegame
      ENTITY event
        UPDATE FIELDS ( quantity mineralvalue )
        WITH VALUE #( ( eventuuid = 'AE0000000000000000000000000000D0' quantity = 1 mineralvalue = 1 )
                      ( eventuuid = 'AE0000000000000000000000000000D1' quantity = 1 mineralvalue = 1 ) )
      FAILED DATA(changed).
    cl_abap_unit_assert=>assert_equals( act = lines( changed-event ) exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = changed-event[ 1 ]-eventuuid exp = CONV sysuuid_x16( 'AE0000000000000000000000000000D0' )
                                        msg = 'repair cost cannot be changed, a production movement can' ).
    MODIFY ENTITIES OF zi_scegame
      ENTITY event
        DELETE FROM VALUE #( ( eventuuid = 'AE0000000000000000000000000000D0' )
                             ( eventuuid = 'AE0000000000000000000000000000D1' ) )
      FAILED DATA(deleted).
    cl_abap_unit_assert=>assert_equals( act = lines( deleted-event ) exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = deleted-event[ 1 ]-eventuuid exp = CONV sysuuid_x16( 'AE0000000000000000000000000000D0' ) ).

    " an update must not turn a movement into unchecked repair cost
    MODIFY ENTITIES OF zi_scegame
      ENTITY division
        CREATE BY \_event
          FIELDS ( eventuuid movementtype material quantity mineralvalue eventsource plantuuid )
          WITH VALUE #( ( divisionuuid = division
                          %target = VALUE #( ( %cid = 'e2' eventuuid = 'AE0000000000000000000000000000D2' movementtype = '101'
                                               material = 'Barracks' quantity = 1 mineralvalue = 150 eventsource = 'LIVE'
                                               plantuuid = plant ) ) ) )
      FAILED DATA(receipt).
    cl_abap_unit_assert=>assert_initial( act = receipt ).
    MODIFY ENTITIES OF zi_scegame
      ENTITY event
        UPDATE FIELDS ( orderuuid )
        WITH VALUE #( ( eventuuid = 'AE0000000000000000000000000000D2' orderuuid = 'AE0000000000000000000000000000C1' ) )
      FAILED DATA(turned).
    cl_abap_unit_assert=>assert_initial( act = turned msg = 'a receipt may be changed; the save decides' ).
    COMMIT ENTITIES RESPONSE OF zi_scegame FAILED DATA(commit_failed) REPORTED DATA(commit_reported).
    cl_abap_unit_assert=>assert_true(
      act = xsdbool( line_exists( commit_failed-event[ eventuuid = 'AE0000000000000000000000000000D2' ] ) )
      msg = 'a 101 with a maintenance order is refused on save' ).
  ENDMETHOD.
ENDCLASS.
