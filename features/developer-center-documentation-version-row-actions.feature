Feature: Developer Center Documentation version row actions

  As an SDK user I should quickly reach the selected SDK release resources and copy the selected markdown from Developer Center Documentation.

  Background:
    Given I am on the Developer Center Documentation page
    And the documentation content has loaded successfully

  Scenario Outline: As an SDK user I should see the version row actions for the selected SDK tab
    When I select the <language> SDK tab
    Then the version row shows GitHub ↗, Release notes ↗, and Copy markdown file
    And GitHub ↗ targets the selected <language> README
    And Release notes ↗ targets the selected <language> release notes URL
    And the version dropdown remains available

    Examples:
      | language |
      | R        |
      | Python   |

  Scenario Outline: As an SDK user I should open the selected README and release notes in a new tab
    Given I have selected the <language> SDK tab
    And I have selected version <version>
    When I click GitHub ↗
    Then the selected README opens in a new browser tab
    And the Developer Center page remains open
    When I click Release notes ↗
    Then the selected release notes page opens in a new browser tab
    And the Developer Center page remains open

    Examples:
      | language | version |
      | R        | current |
      | Python   | current |

  Scenario Outline: As an SDK user I should update the action targets when I change the selected version
    Given I have selected the <language> SDK tab
    And I have selected version <previous_version>
    When I change the version to <new_version>
    Then GitHub ↗ targets the <new_version> README for the selected <language>
    And Release notes ↗ targets the <new_version> release notes URL for the selected <language>
    And Copy markdown file targets the <new_version> markdown content for the selected <language>
    And the documentation content refreshes normally

    Examples:
      | language | previous_version | new_version |
      | R        | current          | next        |
      | Python   | current          | next        |

  Scenario Outline: As an SDK user I should copy the selected markdown content without leaving Developer Center
    Given I have selected the <language> SDK tab
    And I have selected version <version>
    When I click Copy markdown file
    Then the markdown content is copied to the clipboard
    And a success toaster shows "Markdown content copied to clipboard"
    And the Developer Center page remains open

    Examples:
      | language | version |
      | R        | current |
      | Python   | current |

  Scenario: As an SDK user I should not be blocked when markdown is unavailable for the selected version
    Given I have selected an SDK tab and version without markdown content
    When I view the version row actions
    Then Copy markdown file is disabled or shows a clear non-blocking message
    And the Developer Center page remains open

  Scenario: As an SDK user I should keep the version dropdown and documentation load behavior working normally
    Given I am on the Developer Center Documentation page with documentation loaded
    When I change the selected version from the version dropdown
    Then the documentation content loads for the newly selected version
    And the version dropdown remains functional
