# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0

Describe 'Protected validation JSON read model' {
    BeforeAll {
        $script:RepositoryRoot = Split-Path -Parent $PSScriptRoot
        $script:ValidatorPath = Join-Path $script:RepositoryRoot 'scripts/Validate.ps1'
        $tokens = $null
        $parseErrors = $null
        $script:ValidatorAst = [System.Management.Automation.Language.Parser]::ParseFile(
            $script:ValidatorPath, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors.Count -gt 0) { throw "Validate.ps1 did not parse: $($parseErrors -join '; ')" }

        $script:DuplicateCheckAst = @($script:ValidatorAst.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -ceq 'Assert-NoDuplicateJsonProperties'
        }, $true))
        $script:ReadJsonFileAst = @($script:ValidatorAst.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -ceq 'Read-JsonFile'
        }, $true))
        $script:CompatibilityConverterAst = @($script:ValidatorAst.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -ceq 'Convert-JsonElementToPowerShellObject'
        }, $true))
        if ($script:DuplicateCheckAst.Count -ne 1 -or $script:ReadJsonFileAst.Count -ne 1) {
            throw 'Expected exactly one production duplicate check and Read-JsonFile definition.'
        }

        . ([scriptblock]::Create($script:DuplicateCheckAst[0].Extent.Text))
        if ($script:CompatibilityConverterAst.Count -eq 1) {
            . ([scriptblock]::Create($script:CompatibilityConverterAst[0].Extent.Text))
        }
        . ([scriptblock]::Create($script:ReadJsonFileAst[0].Extent.Text))
        $script:FixtureRoot = Join-Path $TestDrive 'validate-json-read-model'
        [void][IO.Directory]::CreateDirectory($script:FixtureRoot)

        function Write-JsonReadFixture {
            param(
                [Parameter(Mandatory)][string] $Name,
                [Parameter(Mandatory)][AllowEmptyString()][string] $Text
            )
            $path = Join-Path $script:FixtureRoot $Name
            [IO.File]::WriteAllText($path, $Text, [Text.UTF8Encoding]::new($false))
            return $path
        }

        function Assert-JsonReadCondition {
            param(
                [Parameter(Mandatory)][bool] $Condition,
                [Parameter(Mandatory)][string] $Message
            )
            if (-not $Condition) { throw $Message }
        }
    }

    AfterAll {
        $testDriveRoot = [IO.Path]::GetFullPath($TestDrive).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
        $testDrivePrefix = $testDriveRoot + [IO.Path]::DirectorySeparatorChar
        $fixtureRoot = [IO.Path]::GetFullPath($script:FixtureRoot)
        if (-not $fixtureRoot.StartsWith($testDrivePrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'The JSON fixture cleanup target is outside the Pester TestDrive.'
        }
        if (Test-Path -LiteralPath $fixtureRoot) {
            Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
        }
        $cleanupSucceeded = -not (Test-Path -LiteralPath $fixtureRoot)
        Write-Host ('JSON_READ_FIXTURE_PATH=' + $fixtureRoot)
        Write-Host ('JSON_READ_FIXTURE_CLEANUP=' + $cleanupSucceeded.ToString().ToLowerInvariant())
        if (-not $cleanupSucceeded) { throw 'The JSON fixture directory was not cleaned.' }
    }

    It 'UnitT10_preserves_valid_setup_timing_JSON_date_strings_and_run_identity' {
        # Scenario: setup-timing.json contains valid UTC and offset timestamps alongside the real timing fields.
        # Purpose: preserve each ISO timestamp string exactly so the existing timing contract can validate it.
        $runId = '5a3f93d4b2744ac8ae35653f9697d24c'
        $startedAtUtc = '2026-10-11T22:13:02.3001452+00:00'
        $capturedAtUtc = '2026-10-11T22:14:03.1234567+10:00'
        $json = '{"schemaVersion":1,"runId":"' + $runId + '","startedAtUtc":"' + $startedAtUtc +
            '","stageTimingCapturedAtUtc":"' + $capturedAtUtc +
            '","stageSeconds":{"closureInventoryHashAndSortSeconds":0.125},"resolverSeconds":{"skill-validator":1.5,"skill-tools":2,"skillspector":3.25},"stageTimingBoundary":"runtime copy and source setup timing"}'
        $path = Write-JsonReadFixture -Name 'setup-timing.json' -Text $json

        $timing = Read-JsonFile -Path $path -Context 'Setup timing'

        Assert-JsonReadCondition ([string]::Equals($timing.runId, $runId, [StringComparison]::Ordinal)) 'runId was not preserved.'
        Assert-JsonReadCondition ($timing.startedAtUtc -is [string]) 'startedAtUtc was not retained as a string.'
        Assert-JsonReadCondition ([string]::Equals($timing.startedAtUtc, $startedAtUtc, [StringComparison]::Ordinal)) 'startedAtUtc changed during JSON read.'
        Assert-JsonReadCondition ($timing.stageTimingCapturedAtUtc -is [string]) 'stageTimingCapturedAtUtc was not retained as a string.'
        Assert-JsonReadCondition ([string]::Equals($timing.stageTimingCapturedAtUtc, $capturedAtUtc, [StringComparison]::Ordinal)) 'stageTimingCapturedAtUtc changed during JSON read.'
        Assert-JsonReadCondition ($timing.stageSeconds.closureInventoryHashAndSortSeconds -eq 0.125) 'The stage numeric value changed.'
        Assert-JsonReadCondition ($timing.resolverSeconds.'skill-validator' -eq 1.5) 'The skill-validator numeric value changed.'
        Assert-JsonReadCondition ($timing.resolverSeconds.'skill-tools' -eq 2) 'The skill-tools numeric value changed.'
        Assert-JsonReadCondition ($timing.resolverSeconds.skillspector -eq 3.25) 'The skillspector numeric value changed.'
    }

    It 'UnitT20_preserves_numeric_JSON_types_arrays_objects_and_null_values' {
        # Scenario: ordinary numeric and collection values share a document with a date-like string.
        # Purpose: retain ConvertFrom-Json numeric types and the existing PSCustomObject/array/null model.
        $json = '{"smallInteger":1,"largeInteger":1234567890123,"fraction":0.125,"dateLike":"2026-10-11T22:13:02.3001452Z","values":[[1,null],{"label":"entry"}],"missing":null}'
        $path = Write-JsonReadFixture -Name 'mixed-values.json' -Text $json
        $expectedNumbers = '{"smallInteger":1,"largeInteger":1234567890123,"fraction":0.125}' | ConvertFrom-Json -Depth 100

        $result = Read-JsonFile -Path $path -Context 'Mixed values'

        foreach ($name in @('smallInteger', 'largeInteger', 'fraction')) {
            $actual = $result.PSObject.Properties[$name].Value
            $expected = $expectedNumbers.PSObject.Properties[$name].Value
            Assert-JsonReadCondition ([string]::Equals($actual.GetType().FullName, $expected.GetType().FullName, [StringComparison]::Ordinal)) "The numeric type for '$name' changed."
            Assert-JsonReadCondition ($actual -eq $expected) "The numeric value for '$name' changed."
        }
        Assert-JsonReadCondition ($result.dateLike -is [string]) 'The date-like value was not retained as a string.'
        Assert-JsonReadCondition ([string]::Equals($result.dateLike, '2026-10-11T22:13:02.3001452Z', [StringComparison]::Ordinal)) 'The date-like value changed during JSON read.'
        Assert-JsonReadCondition ($result.values -is [object[]]) 'The nested values property is not an array.'
        Assert-JsonReadCondition ($result.values[0] -is [object[]]) 'The nested array was not preserved.'
        Assert-JsonReadCondition ($result.values[0].Count -eq 2) 'The nested array length changed.'
        Assert-JsonReadCondition ($result.values[0][0] -eq 1) 'The nested integer changed.'
        Assert-JsonReadCondition ($null -eq $result.values[0][1]) 'The nested null changed.'
        Assert-JsonReadCondition ([string]::Equals($result.values[1].label, 'entry', [StringComparison]::Ordinal)) 'The nested object value changed.'
        Assert-JsonReadCondition ($null -eq $result.missing) 'The null property changed.'
    }

    It 'UnitT30_uses_a_directly_callable_JsonElement_compatibility_converter' {
        # Scenario: the current PowerShell exposes DateKind String, while the supported 7.0 fallback does not.
        # Purpose: directly exercise the production JsonElement converter without replacing JSON parsing.
        if ($script:CompatibilityConverterAst.Count -ne 1) {
            throw 'The production JsonElement compatibility converter is missing.'
        }
        $json = '{"when":"2026-10-11T22:13:02.3001452+00:00","items":[1,null,{"when":"2026-10-11T22:14:03.1234567+10:00"}],"whole":1234567890123,"fraction":0.125,"empty":null}'
        $document = [System.Text.Json.JsonDocument]::Parse($json)
        try {
            $result = Convert-JsonElementToPowerShellObject -Element $document.RootElement
        }
        finally { $document.Dispose() }
        $expectedNumbers = '{"whole":1234567890123,"fraction":0.125}' | ConvertFrom-Json -Depth 100

        Assert-JsonReadCondition ($result.when -is [string]) 'The UTC value was not retained as a string by the compatibility converter.'
        Assert-JsonReadCondition ([string]::Equals($result.when, '2026-10-11T22:13:02.3001452+00:00', [StringComparison]::Ordinal)) 'The UTC value changed in the compatibility converter.'
        Assert-JsonReadCondition ($result.items -is [object[]]) 'The compatibility converter did not preserve an array.'
        Assert-JsonReadCondition ($result.items.Count -eq 3) 'The compatibility converter changed the array length.'
        Assert-JsonReadCondition ($result.items[0] -eq 1) 'The compatibility converter changed the array integer.'
        Assert-JsonReadCondition ($null -eq $result.items[1]) 'The compatibility converter changed the array null.'
        Assert-JsonReadCondition ([string]::Equals($result.items[2].when, '2026-10-11T22:14:03.1234567+10:00', [StringComparison]::Ordinal)) 'The compatibility converter changed the offset value.'
        Assert-JsonReadCondition ([string]::Equals($result.whole.GetType().FullName, $expectedNumbers.whole.GetType().FullName, [StringComparison]::Ordinal)) 'The compatibility converter changed the whole-number type.'
        Assert-JsonReadCondition ($result.whole -eq $expectedNumbers.whole) 'The compatibility converter changed the whole-number value.'
        Assert-JsonReadCondition ([string]::Equals($result.fraction.GetType().FullName, $expectedNumbers.fraction.GetType().FullName, [StringComparison]::Ordinal)) 'The compatibility converter changed the fraction type.'
        Assert-JsonReadCondition ($result.fraction -eq $expectedNumbers.fraction) 'The compatibility converter changed the fraction value.'
        Assert-JsonReadCondition ($null -eq $result.empty) 'The compatibility converter changed the null.'
    }

    It 'UnitT40_rejects_invalid_JSON_and_duplicate_properties_before_returning_a_model' {
        # Scenario: setup evidence is malformed or contains an ambiguous repeated key.
        # Purpose: retain strict JSON and recursive duplicate-property rejection while changing materialization.
        $invalidPath = Write-JsonReadFixture -Name 'invalid.json' -Text '{"startedAtUtc":'
        $duplicatePath = Write-JsonReadFixture -Name 'duplicate.json' -Text '{"outer":{"value":1,"value":2}}'

        $invalidRejected = $false
        try { [void](Read-JsonFile -Path $invalidPath -Context 'Setup timing') }
        catch { $invalidRejected = $_.Exception.Message -like '*not valid unambiguous UTF-8 JSON*' }
        Assert-JsonReadCondition $invalidRejected 'Invalid JSON was accepted.'

        $duplicateRejected = $false
        try { [void](Read-JsonFile -Path $duplicatePath -Context 'Setup timing') }
        catch { $duplicateRejected = $_.Exception.Message -like '*not valid unambiguous UTF-8 JSON*' }
        Assert-JsonReadCondition $duplicateRejected 'Duplicate JSON properties were accepted.'
    }

    It 'UnitT50_rejects_case_colliding_and_empty_object_property_names_in_the_compatibility_converter' {
        # Scenario: JSON object names cannot all be represented as PSCustomObject properties.
        # Purpose: retain ConvertFrom-Json's rejection of case-insensitive collisions and empty names.
        foreach ($json in @('{"a":1,"A":2}', '{"":1}')) {
            $document = [System.Text.Json.JsonDocument]::Parse($json)
            $rejected = $false
            try {
                [void](Convert-JsonElementToPowerShellObject -Element $document.RootElement)
            }
            catch { $rejected = $true }
            finally { $document.Dispose() }

            Assert-JsonReadCondition $rejected "The compatibility converter accepted unsupported object property names in '$json'."
        }
    }
}
