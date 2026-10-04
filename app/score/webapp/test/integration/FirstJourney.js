sap.ui.define([
    "sap/ui/test/opaQunit",
    "./pages/JourneyRunner"
], function (opaTest, runner) {
    "use strict";

    function journey() {
        QUnit.module("First journey");

        opaTest("Start application", function (Given, When, Then) {
            Given.iStartMyApp();

            Then.onTheScoreList.iSeeThisPage();
            Then.onTheScoreList.onFilterBar().iCheckFilterField("Latest game");
            Then.onTheScoreList.onFilterBar().iCheckFilterField("Game");
            Then.onTheScoreList.onFilterBar().iCheckFilterField("Player in game");
            Then.onTheScoreList.onFilterBar().iCheckFilterField("Race");
            Then.onTheScoreList.onTable().iCheckColumns(9, {"GameUUID":{"header":"Game"},"DivisionUUID":{"header":"Player in game"},"GameMinute":{"header":"Minute"},"ArmyValue":{"header":"Army value"},"Workers":{"header":"Workers"},"BankMinerals":{"header":"Bank minerals"},"BankGas":{"header":"Bank gas"},"Collected":{"header":"Collected"},"Lost":{"header":"Lost"}});

        });


        opaTest("Navigate to ObjectPage", function (Given, When, Then) {
            // Note: this test will fail if the ListReport page doesn't show any data
            
            When.onTheScoreList.onFilterBar().iExecuteSearch();
            
            Then.onTheScoreList.onTable().iCheckRows();

            When.onTheScoreList.onTable().iPressRow(0);
            Then.onTheScoreObjectPage.iSeeThisPage();

        });

        opaTest("Teardown", function (Given, When, Then) { 
            // Cleanup
            Given.iTearDownMyApp();
        });
    }

    runner.run([journey]);
});