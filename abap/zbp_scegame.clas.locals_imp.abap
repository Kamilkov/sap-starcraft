*"* use this source file for the definition and implementation of
*"* local helper classes, interface definitions and type
*"* declarations

CLASS lhc_game DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.
    METHODS get_global_authorizations FOR GLOBAL AUTHORIZATION
      IMPORTING REQUEST requested_authorizations FOR game RESULT result.
    METHODS validatereplayhash FOR VALIDATE ON SAVE
      IMPORTING keys FOR game~validatereplayhash.
    METHODS recordresult FOR MODIFY
      IMPORTING keys FOR ACTION game~recordresult.
ENDCLASS.

CLASS lhc_game IMPLEMENTATION.
  METHOD get_global_authorizations.
  ENDMETHOD.

  METHOD recordresult.
    " Plan B's referee reports the match once: winner, duration and every division's result go in one MODIFY, so one save.
    " A failed key fails the action, and RAP then rolls the whole save back: no partial result can be committed.
    READ ENTITIES OF zi_scegame IN LOCAL MODE
      ENTITY game
        FIELDS ( gameuuid ) WITH CORRESPONDING #( keys )
      RESULT DATA(games)
      ENTITY game BY \_division
        FIELDS ( gameuuid gameresult ) WITH CORRESPONDING #( keys )
      RESULT DATA(divisions).

    DATA game_updates TYPE TABLE FOR UPDATE zi_scegame.
    DATA division_updates TYPE TABLE FOR UPDATE zi_scedivision.
    DATA own LIKE divisions.
    LOOP AT keys INTO DATA(key).
      IF NOT line_exists( games[ %tky = key-%tky ] ).
        APPEND VALUE #( %tky = key-%tky ) TO failed-game.
        APPEND VALUE #( %tky = key-%tky
                        %msg = new_message_with_text( severity = if_abap_behv_message=>severity-error
                                                      text     = |Game not found| ) )
               TO reported-game.
        CONTINUE.
      ENDIF.
      own = VALUE #( FOR d IN divisions WHERE ( gameuuid = key-gameuuid ) ( d ) ).
      " a recorded match is final: any division with a result other than UNKNOWN means it was recorded
      DATA(recorded) = abap_false.
      LOOP AT own INTO DATA(recorded_division) WHERE gameresult IS NOT INITIAL AND gameresult <> 'UNKNOWN'.
        recorded = abap_true.
      ENDLOOP.
      IF recorded = abap_true.
        APPEND VALUE #( %tky = key-%tky ) TO failed-game.
        APPEND VALUE #( %tky = key-%tky
                        %msg = new_message_with_text( severity = if_abap_behv_message=>severity-error
                                                      text     = |Result already recorded| ) )
               TO reported-game.
        CONTINUE.
      ENDIF.
      " a void match has no winner, so a winner given with it is not looked at
      DATA(winner) = COND sysuuid_x16( WHEN key-%param-isvoid = abap_true THEN '00000000000000000000000000000000'
                                       ELSE key-%param-winnerdivisionuuid ).
      IF winner IS NOT INITIAL AND NOT line_exists( own[ divisionuuid = winner ] ).
        APPEND VALUE #( %tky = key-%tky ) TO failed-game.
        APPEND VALUE #( %tky = key-%tky
                        %msg = new_message_with_text( severity = if_abap_behv_message=>severity-error
                                                      text     = |Winner is not a division of this game| ) )
               TO reported-game.
        CONTINUE.
      ENDIF.
      APPEND VALUE #( %tky = key-%tky winnerdivisionuuid = winner durationseconds = key-%param-durationseconds )
             TO game_updates.
      LOOP AT own INTO DATA(division).
        APPEND VALUE #( %tky = division-%tky
                        gameresult = COND #( WHEN key-%param-isvoid = abap_true THEN 'VOID'
                                             WHEN winner IS INITIAL THEN 'TIE'
                                             WHEN division-divisionuuid = winner THEN 'WIN'
                                             ELSE 'LOSS' ) )
               TO division_updates.
      ENDLOOP.
    ENDLOOP.

    IF game_updates IS NOT INITIAL.
      MODIFY ENTITIES OF zi_scegame IN LOCAL MODE
        ENTITY game
          UPDATE FIELDS ( winnerdivisionuuid durationseconds ) WITH game_updates
        ENTITY division
          UPDATE FIELDS ( gameresult ) WITH division_updates
        FAILED DATA(update_failed) REPORTED DATA(update_reported).
      failed-game       = CORRESPONDING #( BASE ( failed-game ) update_failed-game ).
      failed-division   = CORRESPONDING #( BASE ( failed-division ) update_failed-division ).
      reported-game     = CORRESPONDING #( BASE ( reported-game ) update_reported-game ).
      reported-division = CORRESPONDING #( BASE ( reported-division ) update_reported-division ).
    ENDIF.
  ENDMETHOD.

  METHOD validatereplayhash.
    READ ENTITIES OF zi_scegame IN LOCAL MODE
      ENTITY game
        FIELDS ( replayhash ) WITH CORRESPONDING #( keys )
      RESULT DATA(games).

    LOOP AT games INTO DATA(game).
      SELECT SINGLE game_uuid FROM zsce_game
        WHERE replay_hash = @game-replayhash
          AND game_uuid  <> @game-gameuuid
        INTO @DATA(existing).
      IF sy-subrc = 0.
        APPEND VALUE #( %tky = game-%tky ) TO failed-game.
        APPEND VALUE #( %tky = game-%tky
                        %msg = new_message_with_text(
                                 severity = if_abap_behv_message=>severity-error
                                 text     = |Replay { game-replayhash } already imported| )
                        %element-replayhash = if_abap_behv=>mk-on )
               TO reported-game.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.
ENDCLASS.

CLASS lcl_pm DEFINITION FINAL.
  PUBLIC SECTION.
    TYPES ty_status TYPE c LENGTH 10.
    "! Why a maintenance order may not go from one status to the reported one; empty when it may.
    "! The same status is allowed (a repeated report); a finished order never moves again.
    CLASS-METHODS transition IMPORTING from         TYPE ty_status
                                       to           TYPE ty_status
                             RETURNING VALUE(error) TYPE string.
    CLASS-METHODS is_final IMPORTING status        TYPE ty_status
                           RETURNING VALUE(result) TYPE abap_bool.
    "! Why the notification outcome does not fit the reported order status; empty when it fits.
    CLASS-METHODS outcome IMPORTING status       TYPE ty_status
                                    outcome      TYPE ty_status
                          RETURNING VALUE(error) TYPE string.
    "! Why priority and health are not acceptable; empty when they are.
    CLASS-METHODS condition IMPORTING priority     TYPE zsce_notif-priority
                                      health       TYPE i
                                      healthmax    TYPE i
                            RETURNING VALUE(error) TYPE string.
    "! Why the tag is no serial number of that material in the division (its receipt is missing), or, with
    "! alive, why it no longer exists (a 551 is posted); empty when it is fine. Reads the ledger.
    CLASS-METHODS serial IMPORTING division     TYPE sysuuid_x16
                                   tag          TYPE zsce_event-unit_tag
                                   material     TYPE zsce_event-matnr
                                   what         TYPE string
                                   alive        TYPE abap_bool DEFAULT abap_true
                         RETURNING VALUE(error) TYPE string.
    "! Why a goods movement is not a valid repair cost posting; empty when it is.
    CLASS-METHODS cost_posting IMPORTING event        TYPE zsce_event
                                         division     TYPE sysuuid_x16
                               RETURNING VALUE(error) TYPE string.
ENDCLASS.

CLASS lcl_pm IMPLEMENTATION.
  METHOD is_final.
    result = xsdbool( status = 'CONFIRMED' OR status = 'CANCELLED' ).
  ENDMETHOD.

  METHOD transition.
    IF to <> 'RELEASED' AND to <> 'STARTED' AND to <> 'CONFIRMED' AND to <> 'CANCELLED'.
      error = |Status { to } cannot be reported|.
    ELSEIF from = to.
      RETURN.
    ELSEIF is_final( from ).
      error = |Order already { from }|.
    ELSEIF from = 'CANCELLING' AND to <> 'CANCELLED' AND to <> 'CONFIRMED'.
      error = |Cancel requested: { to } refused|.
    ELSEIF from <> 'RELEASED' AND from <> 'STARTED' AND from <> 'CANCELLING'.
      error = |Order status { from } unknown|.
    ENDIF.
  ENDMETHOD.

  METHOD outcome.
    DATA(fits) = SWITCH abap_bool( status
                   WHEN 'CONFIRMED' THEN xsdbool( outcome IS INITIAL OR outcome = 'CLOSED' )
                   WHEN 'CANCELLED' THEN xsdbool( outcome = 'OPEN' OR outcome = 'CLOSED' )
                   ELSE xsdbool( outcome IS INITIAL ) ).
    IF fits = abap_false.
      error = |Outcome { outcome } does not fit { status }|.
    ENDIF.
  ENDMETHOD.

  METHOD condition.
    IF priority <> '1' AND priority <> '2' AND priority <> '3'.
      error = |Priority must be 1, 2 or 3|.
    ELSEIF healthmax < 1.
      error = |Health max must be positive|.
    ELSEIF health < 0 OR health > healthmax.
      error = |Health must be between 0 and { healthmax }|.
    ENDIF.
  ENDMETHOD.

  METHOD serial.
    SELECT SINGLE @abap_true FROM zsce_event
      WHERE division_uuid = @division AND unit_tag = @tag AND matnr = @material
        AND ( mvt_type = '101' OR mvt_type = '561' )
      INTO @DATA(received).
    IF sy-subrc <> 0.
      " ponytail: 50-character message limit; a tag has at most 19 digits
      error = |{ what } { tag } unknown|.
      RETURN.
    ENDIF.
    IF alive = abap_true.
      SELECT SINGLE @abap_true FROM zsce_event
        WHERE division_uuid = @division AND unit_tag = @tag AND mvt_type = '551'
        INTO @DATA(scrapped).
      IF sy-subrc = 0.
        error = |{ what } { tag } destroyed|.
      ENDIF.
    ENDIF.
  ENDMETHOD.

  METHOD cost_posting.
    IF event-division_uuid <> division.
      error = |Maintenance order of another division|.
    ELSEIF event-mvt_type <> '261'.
      error = |Repair cost is posted with 261|.
    ELSEIF event-matnr <> 'MINERAL' AND event-matnr <> 'VESPENE'.
      error = |Repair consumes MINERAL or VESPENE|.
    ELSEIF event-quantity < 1.
      error = |Quantity must be positive|.
    ELSEIF ( event-matnr = 'MINERAL' AND ( event-mineral_value <> event-quantity OR event-gas_value <> 0 ) )
        OR ( event-matnr = 'VESPENE' AND ( event-gas_value <> event-quantity OR event-mineral_value <> 0 ) ).
      error = |Value must equal the quantity|.
    ELSEIF event-plant_uuid IS NOT INITIAL.
      error = |Repair cost carries no plant|.
    ELSEIF event-event_source <> 'LIVE'.
      error = |Repair cost comes from a live game|.
    ENDIF.
  ENDMETHOD.
ENDCLASS.

CLASS lhc_event DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.
    METHODS get_instance_features FOR INSTANCE FEATURES
      IMPORTING keys REQUEST requested_features FOR event RESULT result.
    METHODS validatemovementtype FOR VALIDATE ON SAVE
      IMPORTING keys FOR event~validatemovementtype.
    METHODS validatepmevent FOR VALIDATE ON SAVE
      IMPORTING keys FOR event~validatepmevent.
ENDCLASS.

CLASS lhc_event IMPLEMENTATION.
  METHOD get_instance_features.
    " repair cost postings are final; every other movement stays changeable as before
    READ ENTITIES OF zi_scegame IN LOCAL MODE
      ENTITY event
        FIELDS ( orderuuid ) WITH CORRESPONDING #( keys )
      RESULT DATA(events).
    LOOP AT events INTO DATA(event).
      DATA(allowed) = if_abap_behv=>fc-o-enabled.
      IF event-orderuuid IS NOT INITIAL.
        SELECT SINGLE @abap_true FROM zsce_maintord WHERE order_uuid = @event-orderuuid INTO @DATA(found).
        IF sy-subrc = 0.
          allowed = if_abap_behv=>fc-o-disabled.
        ENDIF.
      ENDIF.
      APPEND VALUE #( %tky = event-%tky %update = allowed %delete = allowed ) TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD validatepmevent.
    READ ENTITIES OF zi_scegame IN LOCAL MODE
      ENTITY event
        ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(events).
    LOOP AT events INTO DATA(event) WHERE orderuuid IS NOT INITIAL.
      SELECT SINGLE division_uuid FROM zsce_maintord WHERE order_uuid = @event-orderuuid INTO @DATA(division).
      IF sy-subrc <> 0.
        CONTINUE.   " a production order or none: checked as before
      ENDIF.
      DATA(error) = lcl_pm=>cost_posting( division = division
                                          event    = VALUE #( division_uuid = event-divisionuuid
                                                              plant_uuid    = event-plantuuid
                                                              mvt_type      = event-movementtype
                                                              matnr         = event-material
                                                              quantity      = event-quantity
                                                              mineral_value = event-mineralvalue
                                                              gas_value     = event-gasvalue
                                                              event_source  = event-eventsource ) ).
      IF error IS NOT INITIAL.
        APPEND VALUE #( %tky = event-%tky ) TO failed-event.
        APPEND VALUE #( %tky = event-%tky
                        %msg = new_message_with_text( severity = if_abap_behv_message=>severity-error text = error ) )
               TO reported-event.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.
  METHOD validatemovementtype.
    " ponytail: fixed values live here because the MCP toolset cannot create a DDIC domain
    READ ENTITIES OF zi_scegame IN LOCAL MODE
      ENTITY event
        FIELDS ( movementtype ) WITH CORRESPONDING #( keys )
      RESULT DATA(events).

    LOOP AT events INTO DATA(event).
      CASE event-movementtype.
        WHEN '101' OR '261' OR '262' OR '501' OR '551' OR '561'.
          CONTINUE.
      ENDCASE.
      APPEND VALUE #( %tky = event-%tky ) TO failed-event.
      APPEND VALUE #( %tky = event-%tky
                      %msg = new_message_with_text(
                               severity = if_abap_behv_message=>severity-error
                               text     = |Unknown movement type { event-movementtype }| )
                      %element-movementtype = if_abap_behv=>mk-on )
             TO reported-event.
    ENDLOOP.
  ENDMETHOD.
ENDCLASS.

CLASS lcl_availability DEFINITION FINAL.
  PUBLIC SECTION.
    TYPES: BEGIN OF ty_order,
             key      TYPE sysuuid_x16,
             material TYPE zsce_material-matnr,
             quantity TYPE i,
             mineral  TYPE i,              " cost per unit
             gas      TYPE i,
             blocked  TYPE abap_boolean,
             producer TYPE zsce_material-matnr,
             prereq   TYPE zsce_material-matnr,
           END OF ty_order,
           tt_order TYPE STANDARD TABLE OF ty_order WITH EMPTY KEY,
           tt_name  TYPE SORTED TABLE OF zsce_material-matnr WITH UNIQUE KEY table_line.
    "! new: one division's orders entering RELEASED in this save; committed: cost of its RELEASED orders in the DB
    "! (keys of new excluded); covered: materials on hand >= 1, on a DB order RELEASED/STARTED, or in new.
    "! Returns the first refusal text, empty when the whole set is admitted.
    CLASS-METHODS check IMPORTING new            TYPE tt_order
                                  committed_min  TYPE i
                                  committed_gas  TYPE i
                                  on_hand_min    TYPE i
                                  on_hand_gas    TYPE i
                                  covered        TYPE tt_name
                        RETURNING VALUE(refusal) TYPE string.
    CLASS-METHODS blocked_text IMPORTING material TYPE csequence RETURNING VALUE(text) TYPE string.
    "! Why an order may not enter its status in this save; empty when it may. before: its status in the DB, empty
    "! for a new order. A new RELEASED order is admitted here: check prices it with the rest of its set.
    CLASS-METHODS order_refusal IMPORTING before         TYPE csequence
                                          status         TYPE csequence
                                          quantity       TYPE i
                                RETURNING VALUE(refusal) TYPE string.
ENDCLASS.

CLASS lcl_availability IMPLEMENTATION.
  METHOD order_refusal.
    " the bot moves RELEASED -> STARTED -> CONFIRMED, STARTED -> CANCELLING -> CANCELLED or back to STARTED, and
    " STARTED or CANCELLING back to RELEASED (refund); no other order enters these three, so none walks past check
    IF before IS INITIAL AND quantity < 1.
      refusal = `Quantity must be at least 1`.
    ELSEIF before IS INITIAL AND status <> 'RELEASED' AND status <> 'CONFIRMED'.   " CONFIRMED: replay ingestion
      refusal = |Orders are created RELEASED, not { status }|.
    ELSEIF before IS NOT INITIAL AND ( status = 'RELEASED' OR status = 'STARTED' OR status = 'CANCELLING' )
       AND before <> 'RELEASED' AND before <> 'STARTED' AND before <> 'CANCELLING'.
      refusal = |{ before } order cannot go back to { status }|.
    ENDIF.
  ENDMETHOD.

  METHOD check.
    " ponytail: 50-character message limit; worst cases (5-digit figures, RoboticsFacility) in ltc_availability
    LOOP AT new TRANSPORTING NO FIELDS WHERE quantity < 1.
      refusal = `Quantity must be at least 1`.
      RETURN.
    ENDLOOP.
    LOOP AT new INTO DATA(order) WHERE blocked = abap_true.
      refusal = blocked_text( order-material ).
      RETURN.
    ENDLOOP.
    LOOP AT new INTO order.
      LOOP AT VALUE string_table( ( CONV #( order-producer ) ) ( CONV #( order-prereq ) ) ) INTO DATA(need)
           WHERE table_line IS NOT INITIAL.
        IF NOT line_exists( covered[ table_line = need ] ).
          refusal = |Needs { need }: none on hand or ordered|.
          RETURN.
        ENDIF.
      ENDLOOP.
    ENDLOOP.
    DATA(min) = REDUCE i( INIT s = 0 FOR o IN new NEXT s = s + o-mineral * o-quantity ).
    DATA(gas) = REDUCE i( INIT s = 0 FOR o IN new NEXT s = s + o-gas * o-quantity ).
    IF min > on_hand_min - committed_min.
      refusal = |Over budget: { min } MIN needed, { on_hand_min - committed_min } available|.
    ELSEIF gas > on_hand_gas - committed_gas.
      refusal = |Over budget: { gas } GAS needed, { on_hand_gas - committed_gas } available|.
    ENDIF.
  ENDMETHOD.

  METHOD blocked_text.
    text = |{ material } cannot be ordered|.
  ENDMETHOD.
ENDCLASS.

CLASS lhc_prodorder DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.
    METHODS get_instance_features FOR INSTANCE FEATURES
      IMPORTING keys REQUEST requested_features FOR prodorder RESULT result.
    METHODS cancelorder FOR MODIFY
      IMPORTING keys FOR ACTION prodorder~cancelorder RESULT result.
    METHODS validateavailability FOR VALIDATE ON SAVE
      IMPORTING keys FOR prodorder~validateavailability.
    "! Why the division cannot release these new orders (key, material, quantity); empty when it can.
    METHODS division_refusal IMPORTING division       TYPE sysuuid_x16
                                       new_orders     TYPE lcl_availability=>tt_order
                             RETURNING VALUE(refusal) TYPE string.
ENDCLASS.

CLASS lhc_prodorder IMPLEMENTATION.
  METHOD validateavailability.
    " SAP checks availability when an order is released (CO02); every later status belongs to the bot
    TYPES: BEGIN OF ty_error,
             order TYPE sysuuid_x16,
             text  TYPE string,
           END OF ty_error.
    DATA errors TYPE STANDARD TABLE OF ty_error WITH EMPTY KEY.

    READ ENTITIES OF zi_scegame IN LOCAL MODE
      ENTITY prodorder
        FIELDS ( divisionuuid material quantity orderstatus ) WITH CORRESPONDING #( keys )
      RESULT DATA(orders).

    DATA checked LIKE orders.
    DATA before TYPE zsce_prodord-order_status.
    LOOP AT orders INTO DATA(order).
      CLEAR before.   " stays empty for a new order
      SELECT SINGLE order_status FROM zsce_prodord WHERE order_uuid = @order-orderuuid INTO @before.
      DATA(why) = lcl_availability=>order_refusal( before = before status = order-orderstatus quantity = order-quantity ).
      IF why IS NOT INITIAL.
        APPEND VALUE #( order = order-orderuuid text = why ) TO errors.
      ELSEIF before IS INITIAL AND order-orderstatus = 'RELEASED'.
        APPEND order TO checked.
      ENDIF.
    ENDLOOP.

    " a division's new orders are priced together: one refusal fails all of them
    LOOP AT checked INTO DATA(first) GROUP BY first-divisionuuid INTO DATA(division).
      DATA(new_orders) = VALUE lcl_availability=>tt_order( FOR m IN GROUP division
                                                           ( key = m-orderuuid material = m-material quantity = m-quantity ) ).
      DATA(refusal) = division_refusal( division = division new_orders = new_orders ).
      IF refusal IS NOT INITIAL.
        errors = VALUE #( BASE errors FOR n IN new_orders ( order = n-key text = refusal ) ).
      ENDIF.
    ENDLOOP.

    LOOP AT errors INTO DATA(error).
      APPEND VALUE #( orderuuid = error-order ) TO failed-prodorder.
      APPEND VALUE #( orderuuid            = error-order
                      %msg                 = new_message_with_text( severity = if_abap_behv_message=>severity-error
                                                                    text     = error-text )
                      %element-orderstatus = if_abap_behv=>mk-on )
             TO reported-prodorder.
    ENDLOOP.
  ENDMETHOD.

  METHOD division_refusal.
    " ponytail: stock is the ledger as of the bot's last posting (it lags the game by up to ~28 s)
    READ ENTITIES OF zi_scegame IN LOCAL MODE
      ENTITY division
        FIELDS ( companycode ) WITH VALUE #( ( divisionuuid = division ) )
      RESULT DATA(divisions).
    DATA(company) = VALUE #( divisions[ 1 ]-companycode OPTIONAL ).
    SELECT matnr, mineral_cost, gas_cost, produced_by, prerequisite, order_blocked FROM zsce_material
      WHERE bukrs = @company
      INTO TABLE @DATA(master).

    DATA(priced) = new_orders.
    DATA covered TYPE lcl_availability=>tt_name.
    LOOP AT priced ASSIGNING FIELD-SYMBOL(<new>).
      DATA(row) = VALUE #( master[ matnr = <new>-material ] OPTIONAL ).
      <new>-mineral  = row-mineral_cost.
      <new>-gas      = row-gas_cost.
      <new>-blocked  = xsdbool( row IS INITIAL OR row-order_blocked = abap_true ).   " unknown to the company: blocked
      <new>-producer = row-produced_by.
      <new>-prereq   = row-prerequisite.
      INSERT <new>-material INTO TABLE covered.
    ENDLOOP.

    SELECT material, onhand FROM zi_scedivisionstock
      WHERE divisionuuid = @division
      INTO TABLE @DATA(stock).
    LOOP AT stock INTO DATA(item) WHERE onhand >= 1.
      INSERT item-material INTO TABLE covered.
    ENDLOOP.

    " waiting orders are paid when the bot starts them: their cost is committed; started ones are paid already.
    " The new orders have no DB row yet, so none of them is counted here.
    DATA(committed_min) = 0.
    DATA(committed_gas) = 0.
    SELECT order_uuid, matnr, quantity, order_status FROM zsce_prodord
      WHERE division_uuid = @division AND ( order_status = 'RELEASED' OR order_status = 'STARTED' )
      INTO TABLE @DATA(open).
    LOOP AT open INTO DATA(o).
      INSERT o-matnr INTO TABLE covered.
      IF o-order_status = 'RELEASED'.
        DATA(cost) = VALUE #( master[ matnr = o-matnr ] OPTIONAL ).
        committed_min += cost-mineral_cost * o-quantity.
        committed_gas += cost-gas_cost * o-quantity.
      ENDIF.
    ENDLOOP.

    refusal = lcl_availability=>check( new           = priced
                                       committed_min = committed_min
                                       committed_gas = committed_gas
                                       on_hand_min   = VALUE #( stock[ material = 'MINERAL' ]-onhand OPTIONAL )
                                       on_hand_gas   = VALUE #( stock[ material = 'VESPENE' ]-onhand OPTIONAL )
                                       covered       = covered ).
  ENDMETHOD.

  METHOD get_instance_features.
    " RELEASED is cancelled in SAP, STARTED in the game by the bot; built or already cancelling: no
    READ ENTITIES OF zi_scegame IN LOCAL MODE
      ENTITY prodorder
        FIELDS ( orderstatus ) WITH CORRESPONDING #( keys )
      RESULT DATA(orders).
    result = VALUE #( FOR row IN orders
                      ( %tky                = row-%tky
                        %action-cancelorder = COND #( WHEN row-orderstatus = 'RELEASED' OR row-orderstatus = 'STARTED'
                                                      THEN if_abap_behv=>fc-o-enabled
                                                      ELSE if_abap_behv=>fc-o-disabled ) ) ).
  ENDMETHOD.

  METHOD cancelorder.
    " re-read: the bot may have built the order after Fiori evaluated the button
    READ ENTITIES OF zi_scegame IN LOCAL MODE
      ENTITY prodorder
        FIELDS ( orderstatus ) WITH CORRESPONDING #( keys )
      RESULT DATA(orders).

    LOOP AT orders INTO DATA(row) WHERE orderstatus <> 'RELEASED' AND orderstatus <> 'STARTED'.
      APPEND VALUE #( %tky = row-%tky ) TO failed-prodorder.
      APPEND VALUE #( %tky = row-%tky
                      %msg = new_message_with_text(
                               severity = if_abap_behv_message=>severity-error
                               text     = |Order already { row-orderstatus }| ) )
             TO reported-prodorder.
    ENDLOOP.
    DELETE orders WHERE orderstatus <> 'RELEASED' AND orderstatus <> 'STARTED'.
    IF orders IS INITIAL.
      RETURN.
    ENDIF.

    MODIFY ENTITIES OF zi_scegame IN LOCAL MODE
      ENTITY prodorder
        UPDATE FIELDS ( orderstatus statustext )
        " STARTED: the bot cancels it in the game and answers CANCELLED, or STARTED/CONFIRMED with the reason
        WITH VALUE #( FOR o IN orders ( %tky        = o-%tky
                                        orderstatus = COND #( WHEN o-orderstatus = 'RELEASED' THEN 'CANCELLED' ELSE 'CANCELLING' )
                                        statustext  = COND #( WHEN o-orderstatus = 'RELEASED' THEN 'cancelled in SAP'
                                                                                              ELSE 'cancel requested' ) ) ).

    READ ENTITIES OF zi_scegame IN LOCAL MODE
      ENTITY prodorder
        ALL FIELDS WITH CORRESPONDING #( orders )
      RESULT DATA(cancelled).
    result = VALUE #( FOR c IN cancelled ( %tky = c-%tky %param = c ) ).
  ENDMETHOD.
ENDCLASS.

CLASS lcl_buildable DEFINITION FINAL.
  PUBLIC SECTION.
    "! Why a material is not buildable for a division right now; empty when it is.
    CLASS-METHODS why IMPORTING row TYPE zi_scebuildablematerial RETURNING VALUE(text) TYPE string.
ENDCLASS.

CLASS lcl_buildable IMPLEMENTATION.
  METHOD why.
    IF row-buildable = 'X'.
      RETURN.
    ELSEIF row-producedby IS NOT INITIAL AND row-produceronhand < 1.
      text = |no { row-producedby } on hand yet|.
    ELSEIF row-prerequisite IS NOT INITIAL AND row-prerequisiteonhand < 1.
      text = |requires { row-prerequisite }|.
    ELSEIF row-mineralcost > row-mineralsonhand.
      text = |needs { row-mineralcost } minerals, has { row-mineralsonhand }|.
    ELSE.
      text = |needs { row-gascost } gas, has { row-gasonhand }|.
    ENDIF.
  ENDMETHOD.
ENDCLASS.

CLASS lcl_requirements DEFINITION FINAL.
  PUBLIC SECTION.
    TYPES: BEGIN OF ty_tech,
             material     TYPE zsce_material-matnr,
             producedby   TYPE zsce_material-produced_by,
             prerequisite TYPE zsce_material-prerequisite,
           END OF ty_tech,
           tt_tech      TYPE SORTED TABLE OF ty_tech WITH UNIQUE KEY material,
           tt_materials TYPE STANDARD TABLE OF zsce_material-matnr WITH EMPTY KEY.
    "! What to order before the material because neither stock nor an open order covers it:
    "! its prerequisite and producer, theirs, and so on, dependencies first, each once.
    CLASS-METHODS missing IMPORTING material      TYPE zsce_material-matnr
                                    tech          TYPE tt_tech
                                    covered       TYPE tt_materials
                          RETURNING VALUE(result) TYPE tt_materials.
  PRIVATE SECTION.
    CLASS-METHODS walk IMPORTING material TYPE zsce_material-matnr
                                 tech     TYPE tt_tech
                       CHANGING  seen     TYPE tt_materials
                                 result   TYPE tt_materials.
ENDCLASS.

CLASS lcl_requirements IMPLEMENTATION.
  METHOD missing.
    DATA(seen) = covered.
    APPEND material TO seen.
    walk( EXPORTING material = material tech = tech CHANGING seen = seen result = result ).
  ENDMETHOD.

  METHOD walk.
    READ TABLE tech INTO DATA(row) WITH TABLE KEY material = material.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    LOOP AT VALUE tt_materials( ( row-prerequisite ) ( row-producedby ) ) INTO DATA(need)
         WHERE table_line IS NOT INITIAL.
      IF line_exists( seen[ table_line = need ] ).
        CONTINUE.
      ENDIF.
      APPEND need TO seen.   " before descending, so the SCV <-> CommandCenter loop stops here
      walk( EXPORTING material = need tech = tech CHANGING seen = seen result = result ).
      APPEND need TO result.
    ENDLOOP.
  ENDMETHOD.
ENDCLASS.

CLASS lcl_mrp DEFINITION FINAL.
  PUBLIC SECTION.
    CONSTANTS lot_size   TYPE i VALUE 5.
    CONSTANTS supply_cap TYPE i VALUE 200.
    TYPES: BEGIN OF ty_pir,
             material TYPE zsce_material-matnr,
             quantity TYPE i,
             due      TYPE i,
           END OF ty_pir,
           tt_pirs TYPE STANDARD TABLE OF ty_pir WITH EMPTY KEY,
           BEGIN OF ty_available,
             material TYPE zsce_material-matnr,
             quantity TYPE i,
           END OF ty_available,
           tt_available TYPE STANDARD TABLE OF ty_available WITH EMPTY KEY,
           BEGIN OF ty_master,
             material       TYPE zsce_material-matnr,
             producedby     TYPE zsce_material-produced_by,
             prerequisite   TYPE zsce_material-prerequisite,
             category       TYPE zsce_material-category,
             buildseconds   TYPE i,
             supplycost     TYPE i,
             supplyprovided TYPE i,
             mineralcost    TYPE i,
             blocked        TYPE zsce_material-order_blocked,
           END OF ty_master,
           tt_master TYPE SORTED TABLE OF ty_master WITH UNIQUE KEY material,
           BEGIN OF ty_planned,
             material   TYPE zsce_material-matnr,
             quantity   TYPE i,
             start      TYPE i,
             finish     TYPE i,
             plannedfor TYPE zsce_material-matnr,
             exception  TYPE c LENGTH 40,
           END OF ty_planned,
           tt_planned TYPE STANDARD TABLE OF ty_planned WITH EMPTY KEY,
           BEGIN OF ty_firmed,
             id       TYPE sysuuid_x16,
             material TYPE zsce_material-matnr,
             quantity TYPE i,
             start    TYPE i,
             finish   TYPE i,
           END OF ty_firmed,
           tt_firmed TYPE STANDARD TABLE OF ty_firmed WITH EMPTY KEY,
           BEGIN OF ty_firmed_text,
             id        TYPE sysuuid_x16,
             exception TYPE c LENGTH 40,
           END OF ty_firmed_text,
           tt_firmed_texts TYPE STANDARD TABLE OF ty_firmed_text WITH EMPTY KEY,
           BEGIN OF ty_figures,
             used_now         TYPE i,
             capacity_now     TYPE i,
             used_planned     TYPE i,
             capacity_planned TYPE i,
           END OF ty_figures.
    "! Regenerative MRP for one division (MD01). Firmed planned orders are fixed receipts: they cover targets and
    "! needs but are never changed. A producer or prerequisite planned too late is moved if it is not firmed and
    "! flagged (exception 10) if it is. Supply is planned along the time axis. Infinite capacity, as classic MRP.
    CLASS-METHODS plan IMPORTING clock         TYPE i
                                 pirs          TYPE tt_pirs
                                 available     TYPE tt_available
                                 open          TYPE tt_available OPTIONAL
                                 firmed        TYPE tt_firmed OPTIONAL
                                 master        TYPE tt_master
                       EXPORTING firmed_texts  TYPE tt_firmed_texts
                                 figures       TYPE ty_figures
                       RETURNING VALUE(result) TYPE tt_planned.
    "! The provider a company plans for supply: the lowest mineral cost per supply provided, on a tie the lower name.
    CLASS-METHODS supply_source IMPORTING master        TYPE tt_master
                                RETURNING VALUE(result) TYPE ty_master.
  PRIVATE SECTION.
    TYPES: BEGIN OF ty_order,
             firmed     TYPE abap_bool,
             id         TYPE sysuuid_x16,
             material   TYPE zsce_material-matnr,
             quantity   TYPE i,
             rest       TYPE i,              " firmed: what no target has taken yet
             start      TYPE i,
             finish     TYPE i,
             plannedfor TYPE zsce_material-matnr,
             dependent  TYPE abap_bool,      " planned for another order, not for a target
             placed     TYPE abap_bool,      " has its dates
             late       TYPE abap_bool,      " firmed: finishes after something needs it
             late_for   TYPE i,
             short      TYPE abap_bool,      " Task 3
           END OF ty_order,
           tt_orders TYPE STANDARD TABLE OF ty_order WITH EMPTY KEY,
           " both are indexes of tt_orders, which only grows
           BEGIN OF ty_link,
             needer TYPE i,
             cover  TYPE i,
           END OF ty_link,
           tt_links   TYPE SORTED TABLE OF ty_link WITH UNIQUE KEY needer cover,
           tt_indexes TYPE STANDARD TABLE OF i WITH EMPTY KEY,
           BEGIN OF ty_event,
             time     TYPE i,
             kind     TYPE i,        " 0 = receipt, 1 = requirement: receipts first at the same time
             sequence TYPE i,
             amount   TYPE i,
             order    TYPE i,        " index of tt_orders, 0 for open orders
             material TYPE zsce_material-matnr,
           END OF ty_event,
           tt_events TYPE STANDARD TABLE OF ty_event WITH EMPTY KEY.
    CONSTANTS: receipt     TYPE i VALUE 0,
               requirement TYPE i VALUE 1.
    "! A firmed order is late for the earliest due or start that needs it before it finishes.
    CLASS-METHODS late IMPORTING time  TYPE i
                       CHANGING  order TYPE ty_order.
    "! Does `candidate` need `of`, directly or through other orders? Then it cannot cover a need of `of`.
    CLASS-METHODS in_chain IMPORTING links         TYPE tt_links
                                     of            TYPE i
                                     candidate     TYPE i
                           RETURNING VALUE(result) TYPE abap_bool.
    "! Places new dependents and moves unfirmed orders until every need is met in time or nothing can move.
    CLASS-METHODS schedule IMPORTING master  TYPE tt_master
                                     stocked TYPE lcl_requirements=>tt_materials
                           CHANGING  orders  TYPE tt_orders
                                     links   TYPE tt_links.
    "! Is an order that `of` needs, directly or through other orders, short of supply? Then `of` cannot be built.
    CLASS-METHODS needs_short IMPORTING links         TYPE tt_links
                                        orders        TYPE tt_orders
                                        of            TYPE i
                              RETURNING VALUE(result) TYPE abap_bool.
ENDCLASS.

CLASS lcl_mrp IMPLEMENTATION.
  METHOD plan.
    DATA left TYPE HASHED TABLE OF ty_available WITH UNIQUE KEY material.
    DATA orders TYPE tt_orders.
    DATA links TYPE tt_links.
    DATA needs TYPE lcl_requirements=>tt_materials.
    CLEAR: firmed_texts, figures.
    LOOP AT available INTO DATA(s).
      COLLECT s INTO left.
    ENDLOOP.
    " a blocked material has no place in the tech tree: nothing is proposed for it, and nothing beyond it
    DATA(tech) = VALUE lcl_requirements=>tt_tech( FOR mrow IN master WHERE ( blocked = abap_false )
                                                  ( CORRESPONDING #( mrow ) ) ).
    DATA(blocked) = VALUE lcl_requirements=>tt_materials( FOR brow IN master WHERE ( blocked = abap_true )
                                                          ( brow-material ) ).
    " what stock or an open order covers: no date, so never late
    DATA(stocked) = VALUE lcl_requirements=>tt_materials( FOR l IN left WHERE ( quantity > 0 ) ( l-material ) ).
    DATA(covered) = stocked.

    " firmed planned orders come first, in their sequence: finish, start, key
    DATA(fixed) = firmed.
    SORT fixed STABLE BY finish start id.
    orders = VALUE #( FOR f IN fixed ( firmed = abap_true id = f-id material = f-material quantity = f-quantity
                                       rest = f-quantity start = f-start finish = f-finish placed = abap_true ) ).
    DATA(targets) = pirs.
    SORT targets STABLE BY due.

    " netting: a target takes from stock and open orders, then from firmed orders; its shortage is planned in lots
    LOOP AT targets INTO DATA(target).
      DATA(short) = target-quantity.
      DATA(taken) = 0.
      ASSIGN left[ material = target-material ] TO FIELD-SYMBOL(<left>).
      IF sy-subrc = 0.
        taken = nmin( val1 = <left>-quantity val2 = short ).
        <left>-quantity = <left>-quantity - taken.
        short = short - taken.
      ENDIF.
      LOOP AT orders ASSIGNING FIELD-SYMBOL(<fixed>)
           WHERE firmed = abap_true AND material = target-material AND rest > 0.
        IF short = 0.
          EXIT.
        ENDIF.
        taken = nmin( val1 = <fixed>-rest val2 = short ).
        <fixed>-rest = <fixed>-rest - taken.
        short = short - taken.
        IF target-due < <fixed>-finish.
          late( EXPORTING time = target-due CHANGING order = <fixed> ).
        ENDIF.
      ENDLOOP.
      DATA(item) = VALUE ty_master( master[ material = target-material ] OPTIONAL ).
      DATA(lot) = COND i( WHEN item-category = 'UNIT' THEN lot_size ELSE 1 ).
      WHILE short > 0.
        DATA(q) = nmin( val1 = short val2 = lot ).
        APPEND VALUE #( material = target-material quantity = q placed = abap_true
                        start = target-due - q * item-buildseconds finish = target-due ) TO orders.
        short = short - q.
      ENDWHILE.
    ENDLOOP.

    " what is missing: producers and prerequisites that neither stock, an open order nor a planned order covers
    DATA(planned) = lines( orders ).
    APPEND LINES OF VALUE lcl_requirements=>tt_materials( FOR o IN orders ( o-material ) ) TO covered.
    LOOP AT orders INTO DATA(needing) TO planned.
      DATA(missing) = lcl_requirements=>missing( material = needing-material tech = tech covered = covered ).
      LOOP AT blocked INTO DATA(refused).
        DELETE missing WHERE table_line = refused.
      ENDLOOP.
      APPEND LINES OF missing TO covered.
      APPEND LINES OF missing TO needs.
    ENDLOOP.
    " `needs` lists what is needed before what needs it; the result lists the needing order first, as B.3 did
    DATA(i) = lines( needs ).
    WHILE i > 0.
      APPEND VALUE #( material = needs[ i ] quantity = 1 dependent = abap_true ) TO orders.
      i = i - 1.
    ENDWHILE.

    schedule( EXPORTING master = master stocked = stocked CHANGING orders = orders links = links ).

    " supply at the clock: what stock and open orders provide and use
    DATA events TYPE tt_events.
    DATA unbuilt TYPE HASHED TABLE OF ty_available WITH UNIQUE KEY material.
    DATA(capacity) = 0.
    LOOP AT available INTO DATA(a).
      DATA(am) = VALUE ty_master( master[ material = a-material ] OPTIONAL ).
      capacity         = capacity + a-quantity * am-supplyprovided.
      figures-used_now = figures-used_now + a-quantity * am-supplycost.
    ENDLOOP.
    capacity = nmin( val1 = capacity val2 = supply_cap ).
    figures-capacity_now = capacity.
    " open unit orders are not built yet: they need their supply at the clock, one requirement per material
    DATA(used) = figures-used_now.
    LOOP AT open INTO DATA(waiting).
      COLLECT waiting INTO unbuilt.
    ENDLOOP.
    LOOP AT unbuilt INTO waiting.
      DATA(wm) = VALUE ty_master( master[ material = waiting-material ] OPTIONAL ).
      IF wm-supplycost > 0.
        used = used - waiting-quantity * wm-supplycost.
        APPEND VALUE #( time = clock kind = requirement sequence = lines( events ) + 1
                        amount = waiting-quantity * wm-supplycost material = waiting-material ) TO events.
      ENDIF.
    ENDLOOP.
    SORT events BY material.      " a hashed table has no order of its own
    LOOP AT events ASSIGNING FIELD-SYMBOL(<event>).
      <event>-sequence = sy-tabix.
    ENDLOOP.
    LOOP AT orders INTO DATA(planned_order) WHERE placed = abap_true.
      DATA(index) = sy-tabix.
      DATA(pm) = VALUE ty_master( master[ material = planned_order-material ] OPTIONAL ).
      IF pm-supplyprovided > 0.
        APPEND VALUE #( time = planned_order-finish kind = receipt sequence = lines( events ) + 1
                        amount = planned_order-quantity * pm-supplyprovided order = index ) TO events.
      ENDIF.
      IF pm-supplycost > 0.
        APPEND VALUE #( time = planned_order-start kind = requirement sequence = lines( events ) + 1
                        amount = planned_order-quantity * pm-supplycost order = index
                        material = planned_order-material ) TO events.
      ENDIF.
    ENDLOOP.
    SORT events BY time kind sequence.

    " the source can be built if its producer and prerequisite are in stock or on order; a planned one is not enough
    DATA(source) = supply_source( master ).
    DATA(buildable) = xsdbool( source IS NOT INITIAL
      AND ( source-producedby IS INITIAL OR line_exists( stocked[ table_line = source-producedby ] ) )
      AND ( source-prerequisite IS INITIAL OR line_exists( stocked[ table_line = source-prerequisite ] ) ) ).
    LOOP AT events INTO DATA(event).
      IF event-kind = receipt.
        " a provider whose worker is short of supply cannot be built and delivers nothing. The worker starts
        " before its provider finishes, so its shortage is known here.
        IF needs_short( links = links orders = orders of = event-order ) = abap_false.
          capacity = nmin( val1 = capacity + event-amount val2 = supply_cap ).
        ENDIF.
        CONTINUE.
      ENDIF.
      used = used + event-amount.
      WHILE used > capacity AND capacity < supply_cap AND buildable = abap_true.
        " ponytail: the whole lot needs its supply at its start, so depots come up to four build times early;
        " a requirement per unit if the cap gets tight
        APPEND VALUE #( material = source-material quantity = 1 dependent = abap_true placed = abap_true
                        finish = event-time start = event-time - source-buildseconds
                        plannedfor = event-material ) TO orders.
        capacity = nmin( val1 = capacity + source-supplyprovided val2 = supply_cap ).
      ENDWHILE.
      IF used > capacity AND event-order > 0.
        orders[ event-order ]-short = abap_true.
      ENDIF.
    ENDLOOP.
    figures-used_planned     = used.
    figures-capacity_planned = capacity.

    " exception messages, the first that applies (MD04: 07, 06, then supply, then 10)
    LOOP AT orders INTO DATA(order).
      DATA(text) = COND ty_planned-exception(
                     WHEN order-finish < clock    THEN 'finish in the past'
                     WHEN order-start < clock     THEN 'start in the past'
                     WHEN order-short = abap_true THEN 'short of supply'
                     WHEN order-late = abap_true  THEN |reschedule in to { order-late_for } s| ).
      IF order-firmed = abap_true.
        APPEND VALUE #( id = order-id exception = text ) TO firmed_texts.
      ELSE.
        APPEND VALUE #( material = order-material quantity = order-quantity start = order-start
                        finish = order-finish plannedfor = order-plannedfor exception = text ) TO result.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD late.
    IF order-late = abap_false OR time < order-late_for.
      order-late     = abap_true.
      order-late_for = time.
    ENDIF.
  ENDMETHOD.

  METHOD in_chain.
    " an order is the first member of its own chain: it cannot cover a need of itself
    IF candidate = of.
      result = abap_true.
      RETURN.
    ENDIF.
    " walks from `of` to the orders that need it, and on to the orders that need those; `todo` grows while it is read
    DATA(todo) = VALUE tt_indexes( ( of ) ).
    LOOP AT todo INTO DATA(covering).
      LOOP AT links INTO DATA(link) WHERE cover = covering.
        IF link-needer = candidate.
          result = abap_true.
          RETURN.
        ENDIF.
        IF NOT line_exists( todo[ table_line = link-needer ] ).
          APPEND link-needer TO todo.
        ENDIF.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD schedule.
    " Every link is only added if it closes no cycle, so the links never form one. An order moves only to an earlier
    " finish and only because an order that needs it did, so the moves run out along the links.
    DATA(moved) = abap_true.
    WHILE moved = abap_true.
      moved = abap_false.
      LOOP AT orders INTO DATA(needer) WHERE placed = abap_true.
        DATA(needer_index) = sy-tabix.
        DATA(item) = VALUE ty_master( master[ material = needer-material ] OPTIONAL ).
        LOOP AT VALUE lcl_requirements=>tt_materials( ( item-prerequisite ) ( item-producedby ) ) INTO DATA(need)
             WHERE table_line IS NOT INITIAL.
          IF line_exists( stocked[ table_line = need ] ).
            CONTINUE.
          ENDIF.
          " the orders of the needed material outside the needer's own chain; the first in sequence of each kind
          DATA(timely) = 0.
          DATA(movable) = 0.
          DATA(fixed) = 0.
          LOOP AT orders INTO DATA(candidate) WHERE material = need.
            DATA(candidate_index) = sy-tabix.
            IF in_chain( links = links of = needer_index candidate = candidate_index ).
              CONTINUE.
            ENDIF.
            IF candidate-placed = abap_true AND candidate-finish <= needer-start.
              timely = candidate_index.
              EXIT.
            ELSEIF candidate-firmed = abap_false.
              IF movable = 0 OR candidate-finish < orders[ movable ]-finish
                 OR ( candidate-finish = orders[ movable ]-finish AND candidate-start < orders[ movable ]-start ).
                movable = candidate_index.
              ENDIF.
            ELSEIF fixed = 0.
              fixed = candidate_index.      " firmed orders stand in their sequence already
            ENDIF.
          ENDLOOP.
          DATA(chosen) = COND i( WHEN timely > 0 THEN timely WHEN movable > 0 THEN movable ELSE fixed ).
          IF chosen = 0.
            CONTINUE.       " nothing outside the chain: the worker and the town hall
          ENDIF.
          INSERT VALUE #( needer = needer_index cover = chosen ) INTO TABLE links.
          ASSIGN orders[ chosen ] TO FIELD-SYMBOL(<cover>).
          IF chosen = timely.
            CONTINUE.
          ELSEIF chosen = movable.
            DATA(own) = VALUE ty_master( master[ material = <cover>-material ] OPTIONAL ).
            <cover>-finish = needer-start.
            <cover>-start  = needer-start - <cover>-quantity * own-buildseconds.
            <cover>-placed = abap_true.
            IF <cover>-dependent = abap_true.
              <cover>-plannedfor = needer-material.
            ENDIF.
            moved = abap_true.
          ELSE.
            late( EXPORTING time = needer-start CHANGING order = <cover> ).
          ENDIF.
        ENDLOOP.
      ENDLOOP.
    ENDWHILE.
  ENDMETHOD.

  METHOD supply_source.
    " lowest mineral cost per supply provided, compared without dividing; master is sorted by material, so a tie
    " keeps the lower name
    LOOP AT master INTO DATA(provider) WHERE supplyprovided > 0.
      IF result IS INITIAL
         OR provider-mineralcost * result-supplyprovided < result-mineralcost * provider-supplyprovided.
        result = provider.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD needs_short.
    " walks from `of` to the orders it needs, and on to the orders those need; `todo` grows while it is read
    DATA(todo) = VALUE tt_indexes( ( of ) ).
    LOOP AT todo INTO DATA(needing).
      LOOP AT links INTO DATA(link) WHERE needer = needing.
        IF orders[ link-cover ]-short = abap_true.
          result = abap_true.
          RETURN.
        ENDIF.
        IF NOT line_exists( todo[ table_line = link-cover ] ).
          APPEND link-cover TO todo.
        ENDIF.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.
ENDCLASS.

CLASS lcl_posture DEFINITION FINAL.
  PUBLIC SECTION.
    CONSTANTS threshold TYPE i VALUE 500.
    "! The reason the posture is refused, blank when it is allowed. DEFEND always is; ATTACK needs the army value
    "! (MIN, workers excluded) to reach the threshold.
    CLASS-METHODS refusal IMPORTING posture TYPE csequence army_value TYPE i RETURNING VALUE(text) TYPE string.
ENDCLASS.

CLASS lcl_posture IMPLEMENTATION.
  METHOD refusal.
    " ponytail: 50-character message limit; worst case is 37 (a 10-digit army value)
    text = SWITCH #( posture
             WHEN 'DEFEND' THEN ``
             WHEN 'ATTACK' THEN COND #( WHEN army_value >= threshold THEN ``
                                        ELSE |Army { army_value } MIN, attack needs { threshold }| )
             ELSE |Posture { posture } unknown| ).
  ENDMETHOD.
ENDCLASS.

CLASS lhc_division DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.
    METHODS setposture FOR MODIFY
      IMPORTING keys FOR ACTION division~setposture.
    METHODS releaseorder FOR MODIFY
      IMPORTING keys FOR ACTION division~releaseorder.
    METHODS getdefaultsforreleaseorder FOR READ
      IMPORTING keys FOR FUNCTION division~getdefaultsforreleaseorder RESULT result.
    METHODS planrequirement FOR MODIFY
      IMPORTING keys FOR ACTION division~planrequirement.
    METHODS getdefaultsforplanrequirement FOR READ
      IMPORTING keys FOR FUNCTION division~getdefaultsforplanrequirement RESULT result.
    METHODS runmrp FOR MODIFY
      IMPORTING keys FOR ACTION division~runmrp.
    "! The division's time: the referee's game clock, else (not yet written) the latest event.
    METHODS clock_of IMPORTING division      TYPE sysuuid_x16
                               game_clock    TYPE i
                     RETURNING VALUE(seconds) TYPE i.
ENDCLASS.

CLASS lhc_division IMPLEMENTATION.
  METHOD clock_of.
    IF game_clock > 0.
      seconds = game_clock.
    ELSE.
      SELECT MAX( game_seconds ) FROM zsce_event WHERE division_uuid = @division INTO @seconds.
    ENDIF.
  ENDMETHOD.

  METHOD setposture.
    " the posture is written here and nowhere else (ArmyPosture is read-only); ATTACK is checked against the army value
    READ ENTITIES OF zi_scegame IN LOCAL MODE
      ENTITY division
        FIELDS ( divisionuuid ) WITH CORRESPONDING #( keys )
      RESULT DATA(divisions).

    DATA updates TYPE TABLE FOR UPDATE zi_scedivision.
    LOOP AT keys INTO DATA(key).
      IF NOT line_exists( divisions[ %tky = key-%tky ] ).
        APPEND VALUE #( %tky = key-%tky ) TO failed-division.
        APPEND VALUE #( %tky = key-%tky
                        %msg = new_message_with_text( severity = if_abap_behv_message=>severity-error
                                                      text     = |Division not found| ) )
               TO reported-division.
        CONTINUE.
      ENDIF.
      " a division without army events has no row: army value 0
      SELECT SINGLE armyvaluemin FROM zi_scedivisionarmyvalue
        WHERE divisionuuid = @key-divisionuuid
        INTO @DATA(army).
      IF sy-subrc <> 0.
        army = 0.
      ENDIF.
      DATA(refusal) = lcl_posture=>refusal( posture = key-%param-posture army_value = CONV i( army ) ).
      IF refusal IS NOT INITIAL.
        APPEND VALUE #( %tky = key-%tky ) TO failed-division.
        APPEND VALUE #( %tky = key-%tky
                        %msg = new_message_with_text( severity = if_abap_behv_message=>severity-error
                                                      text     = refusal ) )
               TO reported-division.
        CONTINUE.
      ENDIF.
      APPEND VALUE #( %tky = key-%tky armyposture = key-%param-posture ) TO updates.
    ENDLOOP.

    IF updates IS NOT INITIAL.
      MODIFY ENTITIES OF zi_scegame IN LOCAL MODE
        ENTITY division
          UPDATE FIELDS ( armyposture ) WITH updates
        FAILED DATA(update_failed) REPORTED DATA(update_reported).
      failed-division   = CORRESPONDING #( BASE ( failed-division ) update_failed-division ).
      reported-division = CORRESPONDING #( BASE ( reported-division ) update_reported-division ).
      LOOP AT updates INTO DATA(update).
        IF line_exists( update_failed-division[ %tky = update-%tky ] ).
          CONTINUE.
        ENDIF.
        APPEND VALUE #( %tky = update-%tky
                        %msg = new_message_with_text( severity = if_abap_behv_message=>severity-success
                                                      text     = |Posture { update-armyposture }| ) )
               TO reported-division.
      ENDLOOP.
    ENDIF.
  ENDMETHOD.

  METHOD releaseorder.
    " Fiori releases N orders of quantity 1 (one order per produced unit, as the replay parser does).
    READ ENTITIES OF zi_scegame IN LOCAL MODE
      ENTITY division
        FIELDS ( companycode ) WITH CORRESPONDING #( keys )
      RESULT DATA(divisions).

    DATA orders TYPE TABLE FOR CREATE zi_scedivision\_prodorder.
    DATA n TYPE i.

    LOOP AT keys INTO DATA(key).
      READ TABLE divisions INTO DATA(division) WITH KEY %tky = key-%tky.
      IF sy-subrc <> 0.
        APPEND VALUE #( %tky = key-%tky ) TO failed-division.
        APPEND VALUE #( %tky = key-%tky
                        %msg = new_message_with_text(
                                 severity = if_abap_behv_message=>severity-error
                                 text     = |Division not found| ) )
               TO reported-division.
        CONTINUE.
      ENDIF.
      IF key-%param-quantity < 1.
        APPEND VALUE #( %tky = key-%tky ) TO failed-division.
        APPEND VALUE #( %tky = key-%tky
                        %msg = new_message_with_text(
                                 severity = if_abap_behv_message=>severity-error
                                 text     = |Quantity must be at least 1| ) )
               TO reported-division.
        CONTINUE.
      ENDIF.
      SELECT SINGLE matnr FROM zsce_material
        WHERE matnr = @key-%param-material
          AND bukrs = @division-companycode
        INTO @DATA(matnr).
      IF sy-subrc <> 0.
        APPEND VALUE #( %tky = key-%tky ) TO failed-division.
        APPEND VALUE #( %tky = key-%tky
                        %msg = new_message_with_text(
                                 severity = if_abap_behv_message=>severity-error
                                 text     = |Material { key-%param-material } unknown for company { division-companycode }| ) )
               TO reported-division.
        CONTINUE.
      ENDIF.

      " MRP-style dependent requirements: one order per missing producer/prerequisite, ahead of the N orders
      DATA(prerequisites) = VALUE lcl_requirements=>tt_materials( ).
      IF key-%param-withprerequisites = abap_true.
        DATA tech TYPE lcl_requirements=>tt_tech.
        DATA covered TYPE lcl_requirements=>tt_materials.
        SELECT matnr AS material, produced_by AS producedby, prerequisite FROM zsce_material
          WHERE bukrs = @division-companycode
          INTO CORRESPONDING FIELDS OF TABLE @tech.
        SELECT material FROM zi_scedivisionstock
          WHERE divisionuuid = @key-divisionuuid AND onhand >= 1
          INTO TABLE @covered.
        SELECT matnr FROM zsce_prodord
          WHERE division_uuid = @key-divisionuuid
            AND ( order_status = 'RELEASED' OR order_status = 'STARTED' )
          APPENDING TABLE @covered.
        prerequisites = lcl_requirements=>missing( material = matnr tech = tech covered = covered ).
      ENDIF.

      APPEND VALUE #( %tky = key-%tky ) TO orders ASSIGNING FIELD-SYMBOL(<order>).
      DATA(uuid_failed) = abap_false.
      LOOP AT VALUE lcl_requirements=>tt_materials( BASE prerequisites
                                                    FOR i = 1 UNTIL i > key-%param-quantity ( matnr ) )
           INTO DATA(ordered).
        n += 1.
        TRY.
            DATA(uuid) = cl_system_uuid=>create_uuid_x16_static( ).
          CATCH cx_uuid_error.
            APPEND VALUE #( %tky = key-%tky ) TO failed-division.
            uuid_failed = abap_true.
            EXIT.
        ENDTRY.
        APPEND VALUE #( %cid        = |O{ n }|
                        orderuuid   = uuid
                        material    = ordered
                        quantity    = 1
                        orderstatus = 'RELEASED' )
               TO <order>-%target.
      ENDLOOP.
      IF uuid_failed = abap_true.
        APPEND VALUE #( %tky = key-%tky
                        %msg = new_message_with_text(
                                 severity = if_abap_behv_message=>severity-error
                                 text     = |Could not generate an order number| ) )
               TO reported-division.
        DELETE orders INDEX lines( orders ).
        CONTINUE.
      ENDIF.
      APPEND VALUE #( %tky = key-%tky
                      %msg = new_message_with_text(
                               severity = if_abap_behv_message=>severity-success
                               text     = |{ key-%param-quantity } × { matnr } released| ) )
             TO reported-division.
      LOOP AT prerequisites INTO DATA(prerequisite).
        " ponytail: 50-character message limit; tech names are at most 16 (guarded in ingest/test_live_bot.py)
        APPEND VALUE #( %tky = key-%tky
                        %msg = new_message_with_text(
                                 severity = if_abap_behv_message=>severity-success
                                 text     = |1 × { prerequisite } released (prerequisite)| ) )
               TO reported-division.
      ENDLOOP.
      " The ledger lags the game by up to ~28 s; the order is created anyway and waits in RELEASED.
      SELECT SINGLE * FROM zi_scebuildablematerial
        WHERE divisionuuid = @key-divisionuuid
          AND material     = @matnr
        INTO @DATA(buildable).
      IF sy-subrc = 0 AND buildable-buildable <> 'X'.
        " ponytail: new_message_with_text keeps only 50 characters (SABP_BEHV/100 is a single &1); worst case here is 37
        APPEND VALUE #( %tky = key-%tky
                        %msg = new_message_with_text(
                                 severity = if_abap_behv_message=>severity-warning
                                 text     = |Waits: { lcl_buildable=>why( buildable ) }| ) )
               TO reported-division.
      ENDIF.
    ENDLOOP.

    IF orders IS NOT INITIAL.
      MODIFY ENTITIES OF zi_scegame IN LOCAL MODE
        ENTITY division
          CREATE BY \_prodorder
            FIELDS ( orderuuid material quantity orderstatus ) WITH orders
        MAPPED DATA(create_mapped) FAILED DATA(create_failed) REPORTED DATA(create_reported).
      failed-prodorder   = create_failed-prodorder.
      reported-prodorder = create_reported-prodorder.
    ENDIF.
  ENDMETHOD.

  METHOD getdefaultsforreleaseorder.
    " Fiori calls this before opening the dialog: the hidden DivisionUUID drives the value help, Quantity starts at 1.
    result = VALUE #( FOR key IN keys
                      ( %tky   = key-%tky
                        %param = VALUE #( divisionuuid      = key-divisionuuid
                                          quantity          = 1
                                          withprerequisites = abap_true ) ) ).
  ENDMETHOD.

  METHOD planrequirement.
    " MD61: one PIR per call; the same checks as Release Order, plus a due minute that is not negative
    READ ENTITIES OF zi_scegame IN LOCAL MODE
      ENTITY division
        FIELDS ( companycode ) WITH CORRESPONDING #( keys )
      RESULT DATA(divisions).

    DATA pirs TYPE TABLE FOR CREATE zi_scedivision\_requirement.
    LOOP AT keys INTO DATA(key).
      READ TABLE divisions INTO DATA(division) WITH KEY %tky = key-%tky.
      DATA(error) = COND string( WHEN sy-subrc <> 0              THEN `Division not found`
                                 WHEN key-%param-quantity < 1    THEN `Quantity must be at least 1`
                                 WHEN key-%param-dueminute < 0   THEN `Due minute must not be negative` ).
      IF error IS INITIAL.
        SELECT SINGLE matnr, order_blocked FROM zsce_material
          WHERE matnr = @key-%param-material
            AND bukrs = @division-companycode
          INTO @DATA(item).
        IF sy-subrc <> 0.
          error = |Material { key-%param-material } unknown for company { division-companycode }|.
        ELSEIF item-order_blocked = abap_true.
          error = lcl_availability=>blocked_text( item-matnr ).
        ENDIF.
      ENDIF.
      IF error IS INITIAL.
        TRY.
            DATA(uuid) = cl_system_uuid=>create_uuid_x16_static( ).
          CATCH cx_uuid_error.
            error = `Could not generate a requirement number`.
        ENDTRY.
      ENDIF.
      IF error IS NOT INITIAL.
        APPEND VALUE #( %tky = key-%tky ) TO failed-division.
        APPEND VALUE #( %tky = key-%tky
                        %msg = new_message_with_text( severity = if_abap_behv_message=>severity-error text = error ) )
               TO reported-division.
        CONTINUE.
      ENDIF.
      APPEND VALUE #( %tky    = key-%tky
                      %target = VALUE #( ( %cid            = |R{ lines( pirs ) + 1 }|
                                           requirementuuid = uuid
                                           material        = item-matnr
                                           quantity        = key-%param-quantity
                                           dueseconds      = key-%param-dueminute * 60 ) ) )
             TO pirs.
      " ponytail: 50-character message limit; material names are at most 28 (guarded in ingest/test_live_bot.py)
      APPEND VALUE #( %tky = key-%tky
                      %msg = new_message_with_text(
                               severity = if_abap_behv_message=>severity-success
                               text     = |{ key-%param-quantity } × { item-matnr } due minute { key-%param-dueminute }| ) )
             TO reported-division.
    ENDLOOP.

    IF pirs IS NOT INITIAL.
      MODIFY ENTITIES OF zi_scegame IN LOCAL MODE
        ENTITY division
          CREATE BY \_requirement
            FIELDS ( requirementuuid material quantity dueseconds ) WITH pirs
        FAILED DATA(create_failed) REPORTED DATA(create_reported).
      failed-requirement   = CORRESPONDING #( create_failed-requirement ).
      reported-requirement = CORRESPONDING #( create_reported-requirement ).
    ENDIF.
  ENDMETHOD.

  METHOD getdefaultsforplanrequirement.
    " Fiori calls this before opening the dialog: due five minutes after the division's game clock
    READ ENTITIES OF zi_scegame IN LOCAL MODE
      ENTITY division
        FIELDS ( gameclock ) WITH CORRESPONDING #( keys )
      RESULT DATA(divisions).
    LOOP AT keys INTO DATA(key).
      DATA(clock) = clock_of( division   = key-divisionuuid
                              game_clock = VALUE #( divisions[ divisionuuid = key-divisionuuid ]-gameclock OPTIONAL ) ).
      APPEND VALUE #( %tky   = key-%tky
                      %param = VALUE #( divisionuuid = key-divisionuuid
                                        quantity     = 1
                                        dueminute    = clock DIV 60 + 5 ) )
             TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD runmrp.
    " MD01, regenerative: unfirmed planned orders are deleted and planned anew by lcl_mrp; firmed ones stay
    READ ENTITIES OF zi_scegame IN LOCAL MODE
      ENTITY division
        FIELDS ( companycode gameclock ) WITH CORRESPONDING #( keys )
        RESULT DATA(divisions)
      ENTITY division BY \_requirement
        FIELDS ( divisionuuid material quantity dueseconds ) WITH CORRESPONDING #( keys )
        RESULT DATA(pirs)
      ENTITY division BY \_plannedorder
        FIELDS ( divisionuuid material quantity startseconds finishseconds firmed ) WITH CORRESPONDING #( keys )
        RESULT DATA(old)
      ENTITY division BY \_prodorder
        FIELDS ( divisionuuid material quantity orderstatus ) WITH CORRESPONDING #( keys )
        RESULT DATA(orders).

    DATA planned TYPE TABLE FOR CREATE zi_scedivision\_plannedorder.
    DATA parent TYPE STRUCTURE FOR CREATE zi_scedivision\_plannedorder.
    DATA targets LIKE parent-%target.
    DATA gone TYPE TABLE FOR DELETE zi_sceplannedorder.
    DATA kept TYPE TABLE FOR UPDATE zi_sceplannedorder.
    DATA master TYPE lcl_mrp=>tt_master.
    DATA available TYPE lcl_mrp=>tt_available.
    DATA open TYPE lcl_mrp=>tt_available.
    DATA not_orderable TYPE lcl_requirements=>tt_materials.
    DATA n TYPE i.
    LOOP AT divisions INTO DATA(division).
      DATA(clock) = clock_of( division = division-divisionuuid game_clock = division-gameclock ).
      SELECT matnr AS material, produced_by AS producedby, prerequisite, category, build_seconds AS buildseconds,
             supply_cost AS supplycost, supply_provided AS supplyprovided, mineral_cost AS mineralcost,
             order_blocked AS blocked
        FROM zsce_material
        WHERE bukrs = @division-companycode
        INTO CORRESPONDING FIELDS OF TABLE @master.
      " a PIR of a blocked material is left out of the run; the warning is the trace (a PIR has no exception field)
      DATA(requirements) = VALUE lcl_mrp=>tt_pirs( FOR p IN pirs WHERE ( divisionuuid = division-divisionuuid )
                                                   ( material = p-material quantity = p-quantity due = p-dueseconds ) ).
      CLEAR not_orderable.
      LOOP AT master INTO DATA(blocked_item) WHERE blocked = abap_true.
        DELETE requirements WHERE material = blocked_item-material.
        IF sy-subrc = 0.
          APPEND blocked_item-material TO not_orderable.
        ENDIF.
      ENDLOOP.
      SELECT material, onhand AS quantity FROM zi_scedivisionstock
        WHERE divisionuuid = @division-divisionuuid AND onhand >= 1
        INTO CORRESPONDING FIELDS OF TABLE @available.
      " open production orders cover like stock; CANCELLING is on its way out
      CLEAR open.
      LOOP AT orders INTO DATA(order) WHERE divisionuuid = division-divisionuuid
                                        AND ( orderstatus = 'RELEASED' OR orderstatus = 'STARTED' ).
        APPEND VALUE #( material = order-material quantity = order-quantity ) TO open.
      ENDLOOP.
      APPEND LINES OF open TO available.
      lcl_mrp=>plan( EXPORTING clock     = clock
                               pirs      = requirements
                               available = available
                               open      = open
                               firmed    = VALUE #( FOR f IN old WHERE ( divisionuuid = division-divisionuuid
                                                                        AND firmed = abap_true )
                                                    ( id = f-plannedorderuuid material = f-material quantity = f-quantity
                                                      start = f-startseconds finish = f-finishseconds ) )
                               master    = master
                     IMPORTING firmed_texts = DATA(firmed_texts)
                               figures      = DATA(figures)
                     RECEIVING result       = DATA(plan) ).

      CLEAR targets.
      DATA(uuid_failed) = abap_false.
      LOOP AT plan INTO DATA(row).
        n += 1.
        TRY.
            DATA(uuid) = cl_system_uuid=>create_uuid_x16_static( ).
          CATCH cx_uuid_error.
            uuid_failed = abap_true.
            EXIT.
        ENDTRY.
        APPEND VALUE #( %cid             = |P{ n }|
                        plannedorderuuid = uuid
                        material         = row-material
                        quantity         = row-quantity
                        startseconds     = row-start
                        finishseconds    = row-finish
                        plannedfor       = row-plannedfor
                        exceptiontext    = row-exception ) TO targets.
      ENDLOOP.
      IF uuid_failed = abap_true.
        APPEND VALUE #( %tky = division-%tky ) TO failed-division.
        APPEND VALUE #( %tky = division-%tky
                        %msg = new_message_with_text( severity = if_abap_behv_message=>severity-error
                                                      text     = `Could not generate a planned order number` ) )
               TO reported-division.
        CONTINUE.
      ENDIF.
      CLEAR: planned, gone, kept.
      IF targets IS NOT INITIAL.
        APPEND VALUE #( %tky = division-%tky %target = targets ) TO planned.
      ENDIF.
      LOOP AT old INTO DATA(o) WHERE divisionuuid = division-divisionuuid.
        IF o-firmed = abap_true.
          APPEND VALUE #( %tky          = o-%tky
                          exceptiontext = VALUE #( firmed_texts[ id = o-plannedorderuuid ]-exception OPTIONAL ) )
                 TO kept.
        ELSE.
          APPEND VALUE #( %tky = o-%tky ) TO gone.
        ENDIF.
      ENDLOOP.
      " each division's plan is written on its own, so a failed write fails this division and no other
      MODIFY ENTITIES OF zi_scegame IN LOCAL MODE
        ENTITY plannedorder
          DELETE FROM gone
          UPDATE FIELDS ( exceptiontext ) WITH kept
        ENTITY division
          CREATE BY \_plannedorder
            FIELDS ( plannedorderuuid material quantity startseconds finishseconds plannedfor exceptiontext )
            WITH planned
        FAILED DATA(modify_failed) REPORTED DATA(modify_reported).
      failed-plannedorder   = CORRESPONDING #( BASE ( failed-plannedorder ) modify_failed-plannedorder ).
      reported-plannedorder = CORRESPONDING #( BASE ( reported-plannedorder ) modify_reported-plannedorder ).
      IF modify_failed IS NOT INITIAL.
        " ponytail: only FAILED and REPORTED are mapped. What this division had written before the failure is
        " not taken back here, and what the caller's save does with it is not checked: a write cannot be made
        " to fail from outside. If a real failure shows up, look at FAILED and at the commit response first.
        APPEND VALUE #( %tky = division-%tky ) TO failed-division.
        APPEND VALUE #( %tky = division-%tky
                        %msg = new_message_with_text( severity = if_abap_behv_message=>severity-error
                                                      text     = `MRP could not save the plan` ) )
               TO reported-division.
        CONTINUE.
      ENDIF.
      DATA(exceptions) = REDUCE i( INIT e = 0 FOR r IN plan WHERE ( exception IS NOT INITIAL ) NEXT e = e + 1 )
                       + REDUCE i( INIT e = 0 FOR t IN firmed_texts WHERE ( exception IS NOT INITIAL ) NEXT e = e + 1 ).
      APPEND VALUE #( %tky = division-%tky
                      %msg = new_message_with_text(
                               severity = if_abap_behv_message=>severity-success
                               text     = |MRP at { clock } s: planned orders { lines( plan ) + lines( firmed_texts ) }, | &&
                                          |exceptions { exceptions }| ) )
             TO reported-division.
      " used above capacity shows a shortage, also one of open orders that no planned order can carry
      APPEND VALUE #( %tky = division-%tky
                      %msg = new_message_with_text(
                               severity = if_abap_behv_message=>severity-success
                               text     = |Supply { figures-used_now } of { figures-capacity_now } now, | &&
                                          |{ figures-used_planned } of { figures-capacity_planned } planned| ) )
             TO reported-division.
      " ponytail: 50-character message limit; material names are at most 28
      LOOP AT not_orderable INTO DATA(skipped).
        APPEND VALUE #( %tky = division-%tky
                        %msg = new_message_with_text( severity = if_abap_behv_message=>severity-warning
                                                      text     = |{ skipped }: not orderable| ) )
               TO reported-division.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.
ENDCLASS.

CLASS lhc_requirement DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.
    METHODS deleterequirement FOR MODIFY
      IMPORTING keys FOR ACTION requirement~deleterequirement.
ENDCLASS.

CLASS lhc_requirement IMPLEMENTATION.
  METHOD deleterequirement.
    " its planned orders stay until the next MRP run, as in SAP
    MODIFY ENTITIES OF zi_scegame IN LOCAL MODE
      ENTITY requirement
        DELETE FROM CORRESPONDING #( keys )
      FAILED DATA(delete_failed) REPORTED DATA(delete_reported).
    failed-requirement   = CORRESPONDING #( delete_failed-requirement ).
    reported-requirement = CORRESPONDING #( delete_reported-requirement ).
  ENDMETHOD.
ENDCLASS.

CLASS lhc_plannedorder DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.
    METHODS convertorder FOR MODIFY
      IMPORTING keys FOR ACTION plannedorder~convertorder.
    METHODS firmorder FOR MODIFY
      IMPORTING keys FOR ACTION plannedorder~firmorder.
    METHODS unfirmorder FOR MODIFY
      IMPORTING keys FOR ACTION plannedorder~unfirmorder.
ENDCLASS.

CLASS lhc_plannedorder IMPLEMENTATION.
  METHOD convertorder.
    " CO40/CO41: n single-unit RELEASED production orders per planned order (the bot's model), then it goes
    READ ENTITIES OF zi_scegame IN LOCAL MODE
      ENTITY plannedorder
        FIELDS ( divisionuuid material quantity ) WITH CORRESPONDING #( keys )
      RESULT DATA(planned)
      FAILED DATA(gone).
    failed-plannedorder = CORRESPONDING #( gone-plannedorder ).   " deleted by a newer MRP run: nothing to convert

    DATA orders TYPE TABLE FOR CREATE zi_scedivision\_prodorder.
    DATA n TYPE i.
    LOOP AT planned INTO DATA(p).
      READ TABLE orders ASSIGNING FIELD-SYMBOL(<division>) WITH KEY divisionuuid = p-divisionuuid.
      IF sy-subrc <> 0.
        APPEND VALUE #( divisionuuid = p-divisionuuid ) TO orders ASSIGNING <division>.
      ENDIF.
      DO p-quantity TIMES.
        n += 1.
        TRY.
            DATA(uuid) = cl_system_uuid=>create_uuid_x16_static( ).
          CATCH cx_uuid_error.
            APPEND VALUE #( %tky = p-%tky ) TO failed-plannedorder.
            RETURN.
        ENDTRY.
        APPEND VALUE #( %cid        = |C{ n }|
                        orderuuid   = uuid
                        material    = p-material
                        quantity    = 1
                        orderstatus = 'RELEASED'
                        statustext  = 'converted from planned order' ) TO <division>-%target.
      ENDDO.
      APPEND VALUE #( %tky = p-%tky
                      %msg = new_message_with_text( severity = if_abap_behv_message=>severity-success
                                                    text     = |{ p-quantity } × { p-material } converted| ) )
             TO reported-plannedorder.
    ENDLOOP.
    IF orders IS INITIAL.
      RETURN.
    ENDIF.

    MODIFY ENTITIES OF zi_scegame IN LOCAL MODE
      ENTITY division
        CREATE BY \_prodorder
          FIELDS ( orderuuid material quantity orderstatus statustext ) WITH orders
      ENTITY plannedorder
        DELETE FROM VALUE #( FOR q IN planned ( %tky = q-%tky ) )
      FAILED DATA(modify_failed) REPORTED DATA(modify_reported).
    failed-prodorder   = CORRESPONDING #( modify_failed-prodorder ).
    reported-prodorder = CORRESPONDING #( modify_reported-prodorder ).
  ENDMETHOD.

  METHOD firmorder.
    " a firmed planned order is a fixed receipt: the MRP run keeps it and plans around it
    MODIFY ENTITIES OF zi_scegame IN LOCAL MODE
      ENTITY plannedorder
        UPDATE FIELDS ( firmed ) WITH VALUE #( FOR key IN keys ( %tky = key-%tky firmed = abap_true ) )
      FAILED DATA(update_failed) REPORTED DATA(update_reported).
    failed-plannedorder   = CORRESPONDING #( update_failed-plannedorder ).
    reported-plannedorder = CORRESPONDING #( update_reported-plannedorder ).
  ENDMETHOD.

  METHOD unfirmorder.
    " the next MRP run replaces it
    MODIFY ENTITIES OF zi_scegame IN LOCAL MODE
      ENTITY plannedorder
        UPDATE FIELDS ( firmed ) WITH VALUE #( FOR key IN keys ( %tky = key-%tky firmed = abap_false ) )
      FAILED DATA(update_failed) REPORTED DATA(update_reported).
    failed-plannedorder   = CORRESPONDING #( update_failed-plannedorder ).
    reported-plannedorder = CORRESPONDING #( update_reported-plannedorder ).
  ENDMETHOD.
ENDCLASS.

CLASS lhc_notification DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.
    METHODS get_instance_features FOR INSTANCE FEATURES
      IMPORTING keys REQUEST requested_features FOR notification RESULT result.
    METHODS setopen FOR DETERMINE ON MODIFY
      IMPORTING keys FOR notification~setopen.
    METHODS validatenotification FOR VALIDATE ON SAVE
      IMPORTING keys FOR notification~validatenotification.
    METHODS createorder FOR MODIFY
      IMPORTING keys FOR ACTION notification~createorder RESULT result.
    METHODS reportnotification FOR MODIFY
      IMPORTING keys FOR ACTION notification~reportnotification RESULT result.
ENDCLASS.

CLASS lhc_notification IMPLEMENTATION.
  METHOD get_instance_features.
    READ ENTITIES OF zi_scegame IN LOCAL MODE
      ENTITY notification
        FIELDS ( notificationstatus ) WITH CORRESPONDING #( keys )
      RESULT DATA(rows).
    result = VALUE #( FOR row IN rows
                      ( %tky                = row-%tky
                        %action-createorder = COND #( WHEN row-notificationstatus = 'OPEN'
                                                      THEN if_abap_behv=>fc-o-enabled
                                                      ELSE if_abap_behv=>fc-o-disabled ) ) ).
  ENDMETHOD.

  METHOD setopen.
    " the status is read-only for consumers: whatever a create sends, a new notification is OPEN
    MODIFY ENTITIES OF zi_scegame IN LOCAL MODE
      ENTITY notification
        UPDATE FIELDS ( notificationstatus closedat )
        WITH VALUE #( FOR key IN keys ( %tky = key-%tky notificationstatus = 'OPEN' closedat = 0 ) ).
  ENDMETHOD.

  METHOD validatenotification.
    READ ENTITIES OF zi_scegame IN LOCAL MODE
      ENTITY notification
        ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(rows).
    LOOP AT rows INTO DATA(row).
      " the status is not checked here: setOpen made it OPEN, and createOrder in the same changeset may have moved it on
      DATA(error) = COND string( WHEN row-unittag < 1    THEN `Unit tag must be positive`
                                 WHEN row-reportedat < 0 THEN `Reported at must not be negative` ).
      IF error IS INITIAL.
        error = lcl_pm=>condition( priority = row-priority health = row-health healthmax = row-healthmax ).
      ENDIF.
      IF error IS INITIAL.
        " the division, its plants and its notifications through EML: what this request creates counts too
        READ ENTITIES OF zi_scegame IN LOCAL MODE
          ENTITY division
            FIELDS ( companycode ) WITH VALUE #( ( divisionuuid = row-divisionuuid ) )
            RESULT DATA(divisions)
          ENTITY division BY \_plant
            FIELDS ( plantuuid ) WITH VALUE #( ( divisionuuid = row-divisionuuid ) )
            RESULT DATA(plants)
          ENTITY division BY \_notification
            FIELDS ( notificationuuid unittag notificationstatus ) WITH VALUE #( ( divisionuuid = row-divisionuuid ) )
            RESULT DATA(siblings).
        DATA(company) = VALUE #( divisions[ 1 ]-companycode OPTIONAL ).
        SELECT SINGLE @abap_true FROM zsce_material
          WHERE matnr = @row-material AND bukrs = @company AND category = 'STRUCTURE'
          INTO @DATA(structure).
        IF sy-subrc <> 0.
          " ponytail: 50-character message limit; material names are at most 28 (guarded in ingest/test_live_bot.py)
          error = |{ row-material } is no structure here|.
        ELSEIF row-plantuuid IS NOT INITIAL AND NOT line_exists( plants[ plantuuid = row-plantuuid ] ).
          error = `Plant of another division`.
        ELSE.
          " the receipt may lag the game: the caller keeps the notification pending and sends it again
          error = lcl_pm=>serial( division = row-divisionuuid tag = row-unittag material = row-material
                                  what = `Equipment` ).
        ENDIF.
        " a notification closed in the very request that created it competes with nobody
        IF error IS INITIAL AND row-notificationstatus <> 'CLOSED'.
          LOOP AT siblings TRANSPORTING NO FIELDS
               WHERE unittag = row-unittag AND notificationstatus <> 'CLOSED'
                 AND notificationuuid <> row-notificationuuid.
            error = `Open notification exists`.
            EXIT.
          ENDLOOP.
        ENDIF.
      ENDIF.
      IF error IS NOT INITIAL.
        APPEND VALUE #( %tky = row-%tky ) TO failed-notification.
        APPEND VALUE #( %tky = row-%tky
                        %msg = new_message_with_text( severity = if_abap_behv_message=>severity-error text = error ) )
               TO reported-notification.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD createorder.
    DATA n TYPE i.
    " one key at a time, each read through EML: a second call for the same notification, in this call or later in
    " the same changeset, finds it IN_PROCESS
    LOOP AT keys INTO DATA(key).
      n += 1.
      READ ENTITIES OF zi_scegame IN LOCAL MODE
        ENTITY notification
          ALL FIELDS WITH VALUE #( ( %tky = key-%tky ) )
        RESULT DATA(rows).
      IF rows IS INITIAL.
        APPEND VALUE #( %tky = key-%tky ) TO failed-notification.
        CONTINUE.
      ENDIF.
      DATA(row) = rows[ 1 ].
      READ ENTITIES OF zi_scegame IN LOCAL MODE
        ENTITY division BY \_maintorder
          FIELDS ( notificationuuid orderstatus ) WITH VALUE #( ( divisionuuid = row-divisionuuid ) )
        RESULT DATA(orders).
      DATA(error) = COND string( WHEN row-notificationstatus <> 'OPEN'
                                 THEN |Notification already { row-notificationstatus }| ).
      IF error IS INITIAL.
        LOOP AT orders TRANSPORTING NO FIELDS
             WHERE notificationuuid = row-notificationuuid
               AND ( orderstatus = 'RELEASED' OR orderstatus = 'STARTED' OR orderstatus = 'CANCELLING' ).
          error = `Notification has an open order`.
          EXIT.
        ENDLOOP.
      ENDIF.
      IF error IS INITIAL.
        error = lcl_pm=>serial( division = row-divisionuuid tag = row-unittag material = row-material
                                what = `Equipment` ).
      ENDIF.
      IF error IS INITIAL.
        TRY.
            DATA(uuid) = cl_system_uuid=>create_uuid_x16_static( ).
          CATCH cx_uuid_error.
            error = `Could not generate an order number`.
        ENDTRY.
      ENDIF.
      IF error IS INITIAL.
        SELECT MAX( game_seconds ) FROM zsce_event WHERE division_uuid = @row-divisionuuid INTO @DATA(clock).
        MODIFY ENTITIES OF zi_scegame IN LOCAL MODE
          ENTITY division
            CREATE BY \_maintorder
              FIELDS ( orderuuid notificationuuid unittag material plantuuid orderstatus priority reportedat releasedat )
              WITH VALUE #( ( divisionuuid = row-divisionuuid
                              %target      = VALUE #( ( %cid             = |M{ n }|
                                                        orderuuid        = uuid
                                                        notificationuuid = row-notificationuuid
                                                        unittag          = row-unittag
                                                        material         = row-material
                                                        plantuuid        = row-plantuuid
                                                        orderstatus      = 'RELEASED'
                                                        priority         = row-priority
                                                        reportedat       = row-reportedat
                                                        releasedat       = clock ) ) ) )
          ENTITY notification
            UPDATE FIELDS ( notificationstatus )
            WITH VALUE #( ( %tky = row-%tky notificationstatus = 'IN_PROCESS' ) )
          FAILED DATA(modify_failed).
        IF modify_failed IS NOT INITIAL.
          error = `Repair order could not be created`.
        ENDIF.
      ENDIF.
      IF error IS NOT INITIAL.
        APPEND VALUE #( %tky = key-%tky ) TO failed-notification.
        APPEND VALUE #( %tky = key-%tky
                        %msg = new_message_with_text( severity = if_abap_behv_message=>severity-error text = error ) )
               TO reported-notification.
        CONTINUE.
      ENDIF.
      " ponytail: 50-character message limit; material names are at most 28
      APPEND VALUE #( %tky = key-%tky
                      %msg = new_message_with_text( severity = if_abap_behv_message=>severity-success
                                                    text     = |Repair of { row-material } released| ) )
             TO reported-notification.
    ENDLOOP.

    READ ENTITIES OF zi_scegame IN LOCAL MODE
      ENTITY notification
        ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(after).
    result = VALUE #( FOR a IN after ( %tky = a-%tky %param = a ) ).
  ENDMETHOD.

  METHOD reportnotification.
    LOOP AT keys INTO DATA(key).
      READ ENTITIES OF zi_scegame IN LOCAL MODE
        ENTITY notification
          ALL FIELDS WITH VALUE #( ( %tky = key-%tky ) )
        RESULT DATA(rows).
      IF rows IS INITIAL.
        APPEND VALUE #( %tky = key-%tky ) TO failed-notification.
        CONTINUE.
      ENDIF.
      DATA(row) = rows[ 1 ].
      DATA(report) = key-%param.
      DATA(closing) = xsdbool( report-notificationstatus = 'CLOSED' ).
      DATA(error) = COND string(
        WHEN report-notificationstatus IS NOT INITIAL AND closing = abap_false
        THEN |Status { report-notificationstatus } cannot be reported|
        WHEN report-atseconds < 0
        THEN `At must not be negative` ).
      IF error IS INITIAL.
        error = lcl_pm=>condition( priority = report-priority health = report-health healthmax = report-healthmax ).
      ENDIF.
      IF error IS INITIAL AND row-notificationstatus = 'CLOSED'.
        IF closing = abap_true.
          CONTINUE.     " the close, reported again: nothing changes, and the text of the close stays
        ENDIF.
        error = `Notification already CLOSED`.
      ENDIF.
      IF error IS INITIAL AND closing = abap_false.
        MODIFY ENTITIES OF zi_scegame IN LOCAL MODE
          ENTITY notification
            UPDATE FIELDS ( priority health healthmax statustext )
            WITH VALUE #( ( %tky = row-%tky priority = report-priority health = report-health
                            healthmax = report-healthmax statustext = report-statustext ) ).
      ELSEIF error IS INITIAL.
        READ ENTITIES OF zi_scegame IN LOCAL MODE
          ENTITY division BY \_maintorder
            FIELDS ( notificationuuid orderstatus ) WITH VALUE #( ( divisionuuid = row-divisionuuid ) )
          RESULT DATA(orders).
        DELETE orders WHERE notificationuuid <> row-notificationuuid.
        IF line_exists( orders[ orderstatus = 'STARTED' ] ) OR line_exists( orders[ orderstatus = 'CANCELLING' ] ).
          error = `Repair in work: report the repair`.
        ELSE.
          " an order released a moment ago, which the caller has not seen yet, ends with its notification
          MODIFY ENTITIES OF zi_scegame IN LOCAL MODE
            ENTITY maintorder
              UPDATE FIELDS ( orderstatus statustext )
              WITH VALUE #( FOR o IN orders WHERE ( orderstatus = 'RELEASED' )
                            ( %tky = o-%tky orderstatus = 'CANCELLED' statustext = report-statustext ) )
            ENTITY notification
              UPDATE FIELDS ( notificationstatus closedat priority health healthmax statustext )
              WITH VALUE #( ( %tky = row-%tky notificationstatus = 'CLOSED' closedat = report-atseconds
                              priority = report-priority health = report-health healthmax = report-healthmax
                              statustext = report-statustext ) ).
        ENDIF.
      ENDIF.
      IF error IS NOT INITIAL.
        APPEND VALUE #( %tky = key-%tky ) TO failed-notification.
        APPEND VALUE #( %tky = key-%tky
                        %msg = new_message_with_text( severity = if_abap_behv_message=>severity-error text = error ) )
               TO reported-notification.
      ENDIF.
    ENDLOOP.

    READ ENTITIES OF zi_scegame IN LOCAL MODE
      ENTITY notification
        ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(after).
    result = VALUE #( FOR a IN after ( %tky = a-%tky %param = a ) ).
  ENDMETHOD.
ENDCLASS.

CLASS lhc_maintorder DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.
    METHODS get_instance_features FOR INSTANCE FEATURES
      IMPORTING keys REQUEST requested_features FOR maintorder RESULT result.
    METHODS cancelorder FOR MODIFY
      IMPORTING keys FOR ACTION maintorder~cancelorder RESULT result.
    METHODS reportrepair FOR MODIFY
      IMPORTING keys FOR ACTION maintorder~reportrepair RESULT result.
ENDCLASS.

CLASS lhc_maintorder IMPLEMENTATION.
  METHOD get_instance_features.
    READ ENTITIES OF zi_scegame IN LOCAL MODE
      ENTITY maintorder
        FIELDS ( orderstatus ) WITH CORRESPONDING #( keys )
      RESULT DATA(rows).
    result = VALUE #( FOR row IN rows
                      ( %tky                = row-%tky
                        %action-cancelorder = COND #( WHEN row-orderstatus = 'RELEASED' OR row-orderstatus = 'STARTED'
                                                      THEN if_abap_behv=>fc-o-enabled
                                                      ELSE if_abap_behv=>fc-o-disabled ) ) ).
  ENDMETHOD.

  METHOD cancelorder.
    LOOP AT keys INTO DATA(key).
      " read per key: the bot may have reported, or the same request may have cancelled, a moment ago
      READ ENTITIES OF zi_scegame IN LOCAL MODE
        ENTITY maintorder
          ALL FIELDS WITH VALUE #( ( %tky = key-%tky ) )
        RESULT DATA(rows).
      IF rows IS INITIAL.
        APPEND VALUE #( %tky = key-%tky ) TO failed-maintorder.
        CONTINUE.
      ENDIF.
      DATA(row) = rows[ 1 ].
      IF row-orderstatus = 'STARTED'.
        " the bot stops the SCV and answers CANCELLED, or CONFIRMED when the repair was already done
        MODIFY ENTITIES OF zi_scegame IN LOCAL MODE
          ENTITY maintorder
            UPDATE FIELDS ( orderstatus statustext )
            WITH VALUE #( ( %tky = row-%tky orderstatus = 'CANCELLING' statustext = 'cancel requested' ) ).
      ELSEIF row-orderstatus = 'RELEASED'.
        READ ENTITIES OF zi_scegame IN LOCAL MODE
          ENTITY notification
            FIELDS ( notificationstatus ) WITH VALUE #( ( notificationuuid = row-notificationuuid ) )
          RESULT DATA(notifications).
        MODIFY ENTITIES OF zi_scegame IN LOCAL MODE
          ENTITY maintorder
            UPDATE FIELDS ( orderstatus statustext )
            WITH VALUE #( ( %tky = row-%tky orderstatus = 'CANCELLED' statustext = 'cancelled in SAP' ) )
          ENTITY notification
            UPDATE FIELDS ( notificationstatus )
            WITH VALUE #( FOR n IN notifications WHERE ( notificationstatus = 'IN_PROCESS' )
                          ( %tky = n-%tky notificationstatus = 'OPEN' ) ).
      ELSE.
        APPEND VALUE #( %tky = key-%tky ) TO failed-maintorder.
        APPEND VALUE #( %tky = key-%tky
                        %msg = new_message_with_text( severity = if_abap_behv_message=>severity-error
                                                      text     = |Order already { row-orderstatus }| ) )
               TO reported-maintorder.
      ENDIF.
    ENDLOOP.

    READ ENTITIES OF zi_scegame IN LOCAL MODE
      ENTITY maintorder
        ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(after).
    result = VALUE #( FOR a IN after ( %tky = a-%tky %param = a ) ).
  ENDMETHOD.

  METHOD reportrepair.
    LOOP AT keys INTO DATA(key).
      " the old state is what EML returns now: the transactional buffer over the persisted row
      READ ENTITIES OF zi_scegame IN LOCAL MODE
        ENTITY maintorder
          ALL FIELDS WITH VALUE #( ( %tky = key-%tky ) )
        RESULT DATA(rows).
      IF rows IS INITIAL.
        APPEND VALUE #( %tky = key-%tky ) TO failed-maintorder.
        CONTINUE.
      ENDIF.
      DATA(row) = rows[ 1 ].
      DATA(report) = key-%param.
      DATA(error) = lcl_pm=>transition( from = row-orderstatus to = report-orderstatus ).
      IF error IS INITIAL.
        error = lcl_pm=>outcome( status = report-orderstatus outcome = report-notificationoutcome ).
      ENDIF.
      IF error IS INITIAL.
        error = COND #( WHEN report-workertag < 0 OR report-startedat < 0 OR report-atseconds < 0
                        THEN `Tag and times must not be negative`
                        WHEN report-orderstatus = 'STARTED' AND report-workertag = 0
                        THEN `STARTED needs the SCV tag`
                        WHEN report-orderstatus = 'CONFIRMED' AND report-atseconds < report-startedat
                        THEN `Confirmed before started` ).
      ENDIF.
      IF error IS INITIAL AND report-workertag > 0.
        " a repair starts with an SCV that is alive; a later report may name one that has died since
        error = lcl_pm=>serial( division = row-divisionuuid tag = report-workertag material = 'SCV' what = `SCV`
                                alive = xsdbool( report-orderstatus = 'STARTED' AND row-orderstatus <> 'STARTED' ) ).
      ENDIF.
      IF error IS NOT INITIAL.
        APPEND VALUE #( %tky = key-%tky ) TO failed-maintorder.
        APPEND VALUE #( %tky = key-%tky
                        %msg = new_message_with_text( severity = if_abap_behv_message=>severity-error text = error ) )
               TO reported-maintorder.
        CONTINUE.
      ENDIF.
      IF row-orderstatus = report-orderstatus AND lcl_pm=>is_final( row-orderstatus ) = abap_true.
        CONTINUE.       " a finished order reported again: nothing changes
      ENDIF.

      MODIFY ENTITIES OF zi_scegame IN LOCAL MODE
        ENTITY maintorder
          UPDATE FIELDS ( orderstatus workertag startedat confirmedat statustext )
          WITH VALUE #( ( %tky        = row-%tky
                          orderstatus = report-orderstatus
                          workertag   = COND #( WHEN report-workertag > 0 THEN report-workertag ELSE row-workertag )
                          startedat   = COND #( WHEN report-startedat > 0 THEN report-startedat ELSE row-startedat )
                          confirmedat = COND #( WHEN report-orderstatus = 'CONFIRMED' THEN report-atseconds
                                                ELSE row-confirmedat )
                          statustext  = report-statustext ) ).

      " the notification follows in the same LUW; a closed one is never opened again
      IF lcl_pm=>is_final( report-orderstatus ) = abap_true.
        READ ENTITIES OF zi_scegame IN LOCAL MODE
          ENTITY notification
            FIELDS ( notificationstatus ) WITH VALUE #( ( notificationuuid = row-notificationuuid ) )
          RESULT DATA(notifications).
        DATA(closes) = xsdbool( report-orderstatus = 'CONFIRMED' OR report-notificationoutcome = 'CLOSED' ).
        MODIFY ENTITIES OF zi_scegame IN LOCAL MODE
          ENTITY notification
            UPDATE FIELDS ( notificationstatus closedat statustext )
            WITH VALUE #( FOR n IN notifications WHERE ( notificationstatus <> 'CLOSED' )
                          ( %tky               = n-%tky
                            notificationstatus = COND #( WHEN closes = abap_true THEN 'CLOSED' ELSE 'OPEN' )
                            closedat           = COND #( WHEN closes = abap_true THEN report-atseconds )
                            statustext         = COND #( WHEN report-orderstatus = 'CONFIRMED' THEN 'repaired'
                                                         ELSE report-statustext ) ) ).
      ENDIF.
    ENDLOOP.

    READ ENTITIES OF zi_scegame IN LOCAL MODE
      ENTITY maintorder
        ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(after).
    result = VALUE #( FOR a IN after ( %tky = a-%tky %param = a ) ).
  ENDMETHOD.
ENDCLASS.
