# PowerShell script to parse iteration data
$inputFile = "test_output_parsing.txt"
$outputFile = "iterations_data.csv"

# Initialize arrays
$iterations = @()
$lowerBounds = @()
$upperBounds = @()
$gaps = @()
$cpuTimes = @()

# Track processed iterations to handle duplicates
$processedK = @{}

Write-Host "Parsing iteration data from $inputFile..."

# Read file and process lines
Get-Content $inputFile | ForEach-Object {
    $line = $_
    if ($line -match "^k = ") {
        try {
            # Extract values using regex
            if ($line -match "k = (\d+)\s+LB = ([\d\.e\+\-]+)\s+UB = ([\d\.e\+\-]+)\s+Gap = ([\d\.e\+\-]+)\s+CPU Time = ([\d\.e\+\-]+)") {
                $k = [int]$matches[1]
                
                # Skip if already processed (handle duplicates)
                if ($processedK.ContainsKey($k)) {
                    return
                }
                
                $lb = [double]$matches[2]
                $ub = [double]$matches[3]
                $gap = [double]$matches[4]
                $cpu = [double]$matches[5]
                
                # Store values
                $iterations += $k
                $lowerBounds += $lb
                $upperBounds += $ub
                $gaps += $gap
                $cpuTimes += $cpu
                
                # Mark as processed
                $processedK[$k] = $true
                
                Write-Host "Parsed iteration $k"
            }
        }
        catch {
            Write-Host "Warning: Could not parse line: $line"
        }
    }
}

# Sort data by iteration number
$combinedData = @()
for ($i = 0; $i -lt $iterations.Count; $i++) {
    $combinedData += [PSCustomObject]@{
        Iteration = $iterations[$i]
        LowerBound = $lowerBounds[$i]
        UpperBound = $upperBounds[$i]
        Gap = $gaps[$i]
        CPUTime = $cpuTimes[$i]
    }
}

$sortedData = $combinedData | Sort-Object Iteration

Write-Host "`nParsed Data:"
Write-Host "============"
Write-Host "Number of iterations: $($sortedData.Count)"
Write-Host ""

# Extract sorted arrays
$sortedK = $sortedData | ForEach-Object { $_.Iteration }
$sortedLB = $sortedData | ForEach-Object { $_.LowerBound }
$sortedUB = $sortedData | ForEach-Object { $_.UpperBound }
$sortedGap = $sortedData | ForEach-Object { $_.Gap }
$sortedCPU = $sortedData | ForEach-Object { $_.CPUTime }

Write-Host "Iteration vectors:"
Write-Host "k = @($($sortedK -join ', '))"
Write-Host ""
Write-Host "LB = @($($sortedLB -join ', '))"
Write-Host ""
Write-Host "UB = @($($sortedUB -join ', '))"
Write-Host ""
Write-Host "Gap = @($($sortedGap -join ', '))"
Write-Host ""
Write-Host "CPU Time = @($($sortedCPU -join ', '))"

# Summary statistics
$minK = ($sortedK | Measure-Object -Minimum).Minimum
$maxK = ($sortedK | Measure-Object -Maximum).Maximum
$finalLB = $sortedLB[-1]
$finalUB = $sortedUB[-1]
$finalGap = $sortedGap[-1]
$finalCPU = $sortedCPU[-1]

Write-Host "`nSummary Statistics:"
Write-Host "=================="
Write-Host "Iterations: $minK to $maxK"
Write-Host "Final Lower Bound: $finalLB"
Write-Host "Final Upper Bound: $finalUB"
Write-Host "Final Gap: $([math]::Round($finalGap, 2))%"
Write-Host "Total CPU Time: $([math]::Round($finalCPU, 2)) seconds"
Write-Host "Total CPU Time: $([math]::Round($finalCPU/3600, 2)) hours"

# Save to CSV
Write-Host "`nSaving data to $outputFile..."
$csvContent = "iteration,lower_bound,upper_bound,gap,cpu_time`n"
for ($i = 0; $i -lt $sortedData.Count; $i++) {
    $csvContent += "$($sortedData[$i].Iteration),$($sortedData[$i].LowerBound),$($sortedData[$i].UpperBound),$($sortedData[$i].Gap),$($sortedData[$i].CPUTime)`n"
}
$csvContent | Out-File -FilePath $outputFile -Encoding UTF8
Write-Host "Data saved to $outputFile"