function Get-LenovoBiosSettings {
	[CmdletBinding()]
	
	param(
		[string]$ComputerName
	)
	
	$settings = [PSCustomObject]@{
		_ComputerName = $ComputerName
	}
	
	# Get password state
	# https://docs.lenovocdrt.com/ref/bios/wmi/wmi_guide/#detecting-password-state
	$passSettings = Get-CimInstance -ComputerName $ComputerName -Namespace "root\wmi" -Class "Lenovo_BiosPasswordSettings"
	$settings | Add-Member -NotePropertyName "PassSettings" -NotePropertyValue $passSettings
	
	# Build simplified array of password settings
	$simplifiedPassSettings = $passSettings.PSObject.Properties | Sort "Name" | ForEach-Object {
		$prop = $_
		$propName = $prop.Name
		if($propName -notin "Active","CimClass","CimInstanceProperties","CimSystemProperties","InstanceName","PSComputerName","PSShowComputerName") {
			$newPropName = "Pass_$($prop.Name)"
			[PSCustomObject]@{
				Name = $newPropName
				Value = $prop.Value
			}
		}
	}
	$settings | Add-Member -NotePropertyName "SimplifiedPassSettings" -NotePropertyValue $simplifiedPassSettings
	
	# Get all BIOS settings
	# https://docs.lenovocdrt.com/ref/bios/wmi/wmi_guide/#get-all-current-bios-settings
	$biosSettings = Get-CimInstance -ComputerName $ComputerName -Namespace "root\wmi" -Class "Lenovo_BiosSetting"
	$settings | Add-Member -NotePropertyName "BiosSettings" -NotePropertyValue $biosSettings
	
	# Build simplified array of BIOS settings
	$simplifiedBiosSettings = $biosSettings | ForEach-Object {
		$setting = $_.CurrentSetting
		if(($setting) -and ($setting -ne "")) {
			$settingParts = $setting.Split(",")
			[PSCustomObject]@{
				Name = $settingParts[0]
				Value = $settingParts[1]
			}
		}
	}
	$settings | Add-Member -NotePropertyName "SimplifiedBiosSettings" -NotePropertyValue $simplifiedBiosSettings
	
	# Build overall array of simplified settings
	$settings | Add-Member -NotePropertyName "SimplifiedSettings" -NotePropertyValue (@($simplifiedPassSettings) + @($simplifiedBiosSettings))
	
	# Get possible values for each setting
	
	
	# Output simplified settings
	$settings.SimplifiedSettings | Sort "Name"
}

Export-ModuleMember "Get-LenovoBiosSettings"