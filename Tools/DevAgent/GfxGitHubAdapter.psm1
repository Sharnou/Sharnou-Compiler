$script:GfxRepo='Sharnou/Sharnou-Compiler'
$script:GfxApiBase='https://api.github.com'
$script:GfxApiVersion='2022-11-28'
$script:GfxMaxJsonBytes=8388608
$script:GfxMaxFileBytes=1048576
$script:GfxMaxPages=5
$script:GfxTransportOverride=$null

function Get-GfxCredentialRoot {
 if([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)){throw 'LOCALAPPDATA is unavailable.'}
 return [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'Sharnou\DevAgent\Credentials'))
}
function Get-GfxCredentialPath {return [IO.Path]::Combine((Get-GfxCredentialRoot),'github.token.dpapi')}
function Get-GfxCurrentSid {return [Security.Principal.WindowsIdentity]::GetCurrent().User}
function Set-GfxPrivateAcl {
 param([Parameter(Mandatory=$true)][string]$Path,[switch]$Directory)
 $sid=Get-GfxCurrentSid
 if($Directory){
  $acl=New-Object Security.AccessControl.DirectorySecurity
  $acl.SetAccessRuleProtection($true,$false)
  $rule=New-Object Security.AccessControl.FileSystemAccessRule($sid,[Security.AccessControl.FileSystemRights]::FullControl,([Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit),[Security.AccessControl.PropagationFlags]::None,[Security.AccessControl.AccessControlType]::Allow)
 }else{
  $acl=New-Object Security.AccessControl.FileSecurity
  $acl.SetAccessRuleProtection($true,$false)
  $rule=New-Object Security.AccessControl.FileSystemAccessRule($sid,[Security.AccessControl.FileSystemRights]::FullControl,[Security.AccessControl.AccessControlType]::Allow)
 }
 $acl.SetOwner($sid);$acl.AddAccessRule($rule)
 Set-Acl -LiteralPath $Path -AclObject $acl -ErrorAction Stop
}
function Test-GfxPrivateAcl {
 param([Parameter(Mandatory=$true)][string]$Path,[switch]$Directory)
 try{
  $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
  if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){return $false}
  $acl=Get-Acl -LiteralPath $Path -ErrorAction Stop;$sid=Get-GfxCurrentSid
  if($acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -ne $sid.Value){return $false}
  foreach($rule in $acl.GetAccessRules($true,$false,[Security.Principal.SecurityIdentifier))){
   if($rule.IdentityReference.Value -ne $sid.Value -or $rule.AccessControlType -ne [Security.AccessControl.AccessControlType]::Allow -or (($rule.FileSystemRights -band [Security.AccessControl.FileSystemRights]::FullControl) -ne [Security.AccessControl.FileSystemRights]::FullControl)){return $false}
  }
  return $true
 }catch{return $false}
}
function Get-GfxGitHubCredentialStatus {
 $root=Get-GfxCredentialRoot;$path=Get-GfxCredentialPath
 if(-not(Test-Path -LiteralPath $root -PathType Container)){return [pscustomobject][ordered]@{status='NOT_CONFIGURED';storage='DPAPI_CURRENT_USER';path=$path;aclVerified=$false}}
 if(-not(Test-GfxPrivateAcl -Path $root -Directory)){throw 'Credential directory ACL/reparse-point validation failed.'}
 if(-not(Test-Path -LiteralPath $path -PathType Leaf)){return [pscustomobject][ordered]@{status='NOT_CONFIGURED';storage='DPAPI_CURRENT_USER';path=$path;aclVerified=$true}}
 if(-not(Test-GfxPrivateAcl -Path $path)){throw 'Credential file ACL/reparse-point validation failed.'}
 return [pscustomobject][ordered]@{status='CONFIGURED';storage='DPAPI_CURRENT_USER';path=$path;aclVerified=$true}
}
function Set-GfxGitHubCredential {
 [CmdletBinding()]param([Parameter(Mandatory=$true)][Security.SecureString]$Token)
 if($Token.Length -lt 20 -or $Token.Length -gt 512){throw 'GitHub token length is outside the permitted range.'}
 $root=Get-GfxCredentialRoot
 if(-not(Test-Path -LiteralPath $root -PathType Container)){[void][IO.Directory]::CreateDirectory($root)}
 Set-GfxPrivateAcl -Path $root -Directory
 if(-not(Test-GfxPrivateAcl -Path $root -Directory)){throw 'Could not establish an owner-only credential directory ACL.'}
 $encrypted=ConvertFrom-SecureString -SecureString $Token
 $bytes=(New-Object Text.UTF8Encoding($false)).GetBytes($encrypted)
 $path=Get-GfxCredentialPath;$temp=$path+'.'+[Guid]::NewGuid().ToString('N')+'.tmp'
 $stream=New-Object IO.FileStream($temp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
 try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
 Set-GfxPrivateAcl -Path $temp
 if(Test-Path -LiteralPath $path -PathType Leaf){[IO.File]::Replace($temp,$path,$null,$true)}else{[IO.File]::Move($temp,$path)}
 if(-not(Test-GfxPrivateAcl -Path $path)){throw 'Credential file ACL verification failed.'}
 return [pscustomobject][ordered]@{status='CONFIGURED';storage='DPAPI_CURRENT_USER';aclVerified=$true;secretReturned=$false}
}
function Remove-GfxGitHubCredential {
 $path=Get-GfxCredentialPath;$root=Get-GfxCredentialRoot
 if(Test-Path -LiteralPath $root -PathType Container){
  if(-not(Test-GfxPrivateAcl -Path $root -Directory)){throw 'Credential directory ACL validation failed; refusing deletion.'}
  if(Test-Path -LiteralPath $path -PathType Leaf){
   if(-not(Test-GfxPrivateAcl -Path $path)){throw 'Credential file ACL validation failed; refusing deletion.'}
   [IO.File]::Delete($path)
  }
 }
 return [pscustomobject][ordered]@{status='NOT_CONFIGURED';secretReturned=$false}
}
function Get-GfxAuthToken {
 $status=Get-GfxGitHubCredentialStatus
 if($status.status -ne 'CONFIGURED'){return $null}
 $secure=$null;$bstr=[IntPtr]::Zero
 try{
  $encrypted=[IO.File]::ReadAllText((Get-GfxCredentialPath),(New-Object Text.UTF8Encoding($false,$true)))
  $secure=ConvertTo-SecureString -String $encrypted -ErrorAction Stop
  $bstr=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  $token=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
  if($token -notmatch '^[\x21-\x7e]{20,512}$'){throw 'Stored GitHub credential failed validation.'}
  return $token
 }catch{throw 'Stored GitHub credential could not be decrypted or validated.'}
 finally{if($bstr -ne [IntPtr]::Zero){[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)};if($null -ne $secure){$secure.Dispose()}}
}
function Read-GfxResponseBytes {
 param([Parameter(Mandatory=$true)][IO.Stream]$Stream,[int]$MaxBytes)
 $memory=New-Object IO.MemoryStream;$buffer=New-Object byte[] 65536;$total=0
 try{
  while(($read=$Stream.Read($buffer,0,$buffer.Length)) -gt 0){
   $total+=$read;if($total -gt $MaxBytes){throw "Response exceeded the $MaxBytes byte limit."}
   $memory.Write($buffer,0,$read)
  }
  return ,$memory.ToArray()
 }finally{$memory.Dispose()}
}
function Invoke-GfxHttpGet {
 param([Parameter(Mandatory=$true)][Uri]$Uri,[bool]$SendAuth=$true,[int]$MaxBytes=8388608,[string]$Accept='application/vnd.github+json')
 if($Uri.Scheme -ne 'https'){throw 'Only HTTPS requests are permitted.'}
 if($Uri.Host -cne 'api.github.com'){throw 'Only the fixed GitHub API host is permitted.'}
 if($null -ne $script:GfxTransportOverride){
  $mock=& $script:GfxTransportOverride $Uri.AbsoluteUri $SendAuth $MaxBytes
  if($null -eq $mock -or $null -eq $mock.StatusCode -or $null -eq $mock.BodyBytes){throw 'Test transport returned an invalid response.'}
  if($mock.BodyBytes.Length -gt $MaxBytes){throw 'Mock response exceeded configured byte limit.'}
  return $mock
 }
 $request=[Net.HttpWebRequest]::Create($Uri);$request.Method='GET';$request.AllowAutoRedirect=$false
 $request.Accept=$Accept;$request.UserAgent='SharnouDevAgent-GfxReadOnlyAdapter/1.0'
 $request.Timeout=20000;$request.ReadWriteTimeout=20000
 $request.Headers['X-GitHub-Api-Version']=$script:GfxApiVersion
 $request.AutomaticDecompression=[Net.DecompressionMethods]::GZip -bor [Net.DecompressionMethods]::Deflate
 $token=$null
 try{
  if($SendAuth){$token=Get-GfxAuthToken;if(-not[string]::IsNullOrEmpty($token)){$request.Headers['Authorization']='Bearer '+$token}}
  $response=$null
  try{$response=[Net.HttpWebResponse]$request.GetResponse()}
  catch [Net.WebException]{
   if($null -eq $_.Exception.Response){throw 'GitHub HTTPS transport failed.'}
   $response=[Net.HttpWebResponse]$_.Exception.Response
  }
  try{
   $status=[int]$response.StatusCode;$body=[byte[]]@()
   if($status -ge 200 -and $status -lt 300 -and $null -ne $response.GetResponseStream()){$body=Read-GfxResponseBytes -Stream $response.GetResponseStream() -MaxBytes $MaxBytes}
   $headers=@{requestId=[string]$response.Headers['X-GitHub-Request-Id'];retryAfter=[string]$response.Headers['Retry-After'];rateLimitReset=[string]$response.Headers['X-RateLimit-Reset']}
   return [pscustomobject][ordered]@{StatusCode=$status;ContentType=[string]$response.ContentType;BodyBytes=$body;Location=[string]$response.Headers['Location'];Headers=$headers}
  }finally{$response.Close()}
 }catch{if($_.Exception.Message -match 'byte limit'){throw};throw 'GitHub HTTPS request failed; details were suppressed to avoid credential disclosure.'}
 finally{$token=$null}
}
function New-GfxApiUri {
 param([Parameter(Mandatory=$true)][string]$Path,[string]$Query='')
 if($Path.StartsWith('/') -or $Path.Contains('..') -or $Path.Contains('\') -or $Path -match '[\x00-\x20]'){throw 'API path failed fixed-route validation.'}
 $uriText=$script:GfxApiBase+'/repos/'+$script:GfxRepo+'/'+$Path
 if(-not[string]::IsNullOrEmpty($Query)){$uriText+='?'+$Query}
 return [Uri]$uriText
}
function Invoke-GfxApiJson {
 param([Parameter(Mandatory=$true)][string]$Path,[string]$Query='')
 $uri=New-GfxApiUri -Path $Path -Query $Query
 $response=Invoke-GfxHttpGet -Uri $uri -SendAuth $true -MaxBytes $script:GfxMaxJsonBytes
 if($response.StatusCode -lt 200 -or $response.StatusCode -ge 300){
  $requestId='';if($null -ne $response.Headers){$requestId=[string]$response.Headers.requestId}
  throw ("GitHub API returned HTTP {0}; requestId={1}. No response body was retained." -f $response.StatusCode,$requestId)
 }
 if($response.BodyBytes.Length -eq 0){throw 'GitHub API returned an empty response.'}
 try{return (ConvertFrom-Json -InputObject ([Text.Encoding]::UTF8.GetString([byte[]]$response.BodyBytes)) -ErrorAction Stop)}
 catch{throw 'GitHub API returned malformed JSON.'}
}
function Get-GfxGitHubRepository {
 $r=Invoke-GfxApiJson -Path ''
 if($r.full_name -cne $script:GfxRepo -or $null -eq $r.id -or [string]::IsNullOrWhiteSpace([string]$r.default_branch)){throw 'GitHub repository identity failed validation.'}
 return [pscustomobject][ordered]@{repository=$r.full_name;repositoryId=[long]$r.id;defaultBranch=[string]$r.default_branch;visibility=[string]$r.visibility;archived=[bool]$r.archived;private=[bool]$r.private;htmlUrl=[string]$r.html_url;capturedAtUtc=[DateTime]::UtcNow.ToString('o',[Globalization.CultureInfo]::InvariantCulture)}
}
function Assert-GfxBranchName {
 param([string]$Name)
 if([string]::IsNullOrWhiteSpace($Name) -or $Name.Length -gt 120 -or $Name -notmatch '^[A-Za-z0-9][A-Za-z0-9._/-]*$' -or $Name -match '(\.\.|//|/$|@\{|\\)'){throw 'Branch name is invalid.'}
}
function Get-GfxGitHubBranch {
 [CmdletBinding()]param([Parameter(Mandatory=$true)][string]$BranchName)
 Assert-GfxBranchName $BranchName
 $r=Invoke-GfxApiJson -Path ('branches/'+[Uri]::EscapeDataString($BranchName))
 if($r.name -cne $BranchName -or $null -eq $r.commit.sha -or $r.commit.sha -notmatch '^[0-9a-f]{40}$'){throw 'Branch response identity failed validation.'}
 return [pscustomobject][ordered]@{repository=$script:GfxRepo;branch=$BranchName;commitSha=[string]$r.commit.sha;protected=[bool]$r.protected;commitUrl=[string]$r.commit.url;capturedAtUtc=[DateTime]::UtcNow.ToString('o',[Globalization.CultureInfo]::InvariantCulture)}
}
function Assert-GfxGitRef {
 param([string]$Ref)
 if([string]::IsNullOrWhiteSpace($Ref) -or $Ref.Length -gt 120 -or $Ref -match '[\x00-\x20?#]' -or $Ref -match '(^/|//|\\.\\.|\\\\|@\{)'){throw 'Git ref is invalid.'}
}
function Get-GfxGitHubCommit {
 [CmdletBinding()]param([Parameter(Mandatory=$true)][string]$Ref)
 Assert-GfxGitRef $Ref
 $r=Invoke-GfxApiJson -Path ('commits/'+[Uri]::EscapeDataString($Ref))
 if($r.sha -notmatch '^[0-9a-f]{40}$' -or $r.commit.tree.sha -notmatch '^[0-9a-f]{40}$'){throw 'Commit response is missing canonical SHA identities.'}
 $messageBytes=(New-Object Text.UTF8Encoding($false)).GetBytes([string]$r.commit.message)
 $messageHash=[BitConverter]::ToString(([Security.Cryptography.SHA256]::Create()).ComputeHash($messageBytes)).Replace('-','').ToLowerInvariant()
 return [pscustomobject][ordered]@{repository=$script:GfxRepo;sha=[string]$r.sha;treeSha=[string]$r.commit.tree.sha;messageSha256=$messageHash;authorDateUtc=[string]$r.commit.author.date;committerDateUtc=[string]$r.commit.committer.date;htmlUrl=[string]$r.html_url;capturedAtUtc=[DateTime]::UtcNow.ToString('o',[Globalization.CultureInfo]::InvariantCulture)}
}
function Assert-GfxRepoPath {
 param([string]$Path)
 if([string]::IsNullOrWhiteSpace($Path) -or $Path.Length -gt 512 -or $Path.StartsWith('/') -or $Path.StartsWith('\') -or $Path.Contains('\') -or $Path -match '[\x00-\x20?#:]' -or $Path -match '(^|/)\.\.?(/|$)' -or $Path -match '%'){throw 'Repository path is invalid.'}
 foreach($segment in $Path.Split('/')){if($segment.Length -eq 0 -or $segment -eq '.' -or $segment -eq '..'){throw 'Repository path contains an invalid segment.'}}
}
function Get-GfxGitHubFile {
 [CmdletBinding()]param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)][string]$Ref,[int]$MaxBytes=1048576)
 Assert-GfxRepoPath $Path;Assert-GfxGitRef $Ref
 if($MaxBytes -lt 1 -or $MaxBytes -gt $script:GfxMaxFileBytes){throw 'File byte limit must be between 1 byte and 1 MiB.'}
 $commit=Get-GfxGitHubCommit -Ref $Ref
 $escaped=(@($Path.Split('/')|ForEach-Object{[Uri]::EscapeDataString($_)}) -join '/')
 $r=Invoke-GfxApiJson -Path ('contents/'+$escaped) -Query ('ref='+$commit.sha)
 if($r.type -cne 'file' -or $r.encoding -cne 'base64' -or [string]::IsNullOrWhiteSpace([string]$r.content)){throw 'GitHub content response is not a supported base64 file.'}
 if([long]$r.size -lt 0 -or [long]$r.size -gt $MaxBytes){throw 'Source file exceeds configured byte limit.'}
 try{$bytes=[Convert]::FromBase64String(([string]$r.content -replace '\s',''))}catch{throw 'GitHub source file Base64 payload is malformed.'}
 if($bytes.Length -gt $MaxBytes -or $bytes.Length -ne [long]$r.size){throw 'GitHub source file length does not match metadata or the configured limit.'}
 $gitPrefix=(New-Object Text.UTF8Encoding($false)).GetBytes('blob '+[string]$bytes.Length+[char]0)
 $gitBytes=New-Object byte[] ($gitPrefix.Length+$bytes.Length)
 [Buffer]::BlockCopy($gitPrefix,0,$gitBytes,0,$gitPrefix.Length);[Buffer]::BlockCopy($bytes,0,$gitBytes,$gitPrefix.Length,$bytes.Length)
 $sha1=[BitConverter]::ToString(([Security.Cryptography.SHA1]::Create()).ComputeHash($gitBytes)).Replace('-','').ToLowerInvariant()
 if($sha1 -cne [string]$r.sha){throw 'GitHub blob SHA-1 does not match the exact returned bytes.'}
 $sha256=[BitConverter]::ToString(([Security.Cryptography.SHA256]::Create()).ComputeHash($bytes)).Replace('-','').ToLowerInvariant()
 try{$text=(New-Object Text.UTF8Encoding($false,$true)).GetString($bytes)}catch{throw 'Source file is not valid UTF-8 text.'}
 return [pscustomobject][ordered]@{repository=$script:GfxRepo;path=$Path;requestedRef=$Ref;commitSha=$commit.sha;gitBlobSha=$sha1;contentSha256=$sha256;byteCount=$bytes.Length;content=$text;capturedAtUtc=[DateTime]::UtcNow.ToString('o',[Globalization.CultureInfo]::InvariantCulture)}
}
function Get-GfxGitHubPullRequest {
 [CmdletBinding()]param([Parameter(Mandatory=$true)][ValidateRange(1,2147483647)][int]$PullRequestNumber)
 $r=Invoke-GfxApiJson -Path ('pulls/'+$PullRequestNumber)
 if([int]$r.number -ne $PullRequestNumber -or [string]$r.base.repo.full_name -cne $script:GfxRepo -or [string]$r.head.repo.full_name -cne $script:GfxRepo -or [string]$r.head.sha -notmatch '^[0-9a-f]{40}$'){throw 'Pull request response identity failed validation.'}
 return [pscustomobject][ordered]@{repository=$script:GfxRepo;number=$PullRequestNumber;state=[string]$r.state;draft=[bool]$r.draft;merged=($null -ne $r.merged_at);baseBranch=[string]$r.base.ref;headBranch=[string]$r.head.ref;headSha=[string]$r.head.sha;baseSha=[string]$r.base.sha;htmlUrl=[string]$r.html_url;createdAtUtc=[string]$r.created_at;updatedAtUtc=[string]$r.updated_at;mergedAtUtc=[string]$r.merged_at;capturedAtUtc=[DateTime]::UtcNow.ToString('o',[Globalization.CultureInfo]::InvariantCulture)}
}
function Get-GfxGitHubPullRequests {
 [CmdletBinding()]param([ValidateSet('open','closed','all')][string]$State='all',[ValidateRange(1,100)][int]$PerPage=100)
 $items=New-Object Collections.ArrayList
 for($page=1;$page -le $script:GfxMaxPages;$page++){
  $r=Invoke-GfxApiJson -Path 'pulls' -Query ("state=$State&per_page=$PerPage&page=$page")
  if($r -isnot [Array]){throw 'Pull request collection response is not an array.'}
  foreach($pr in $r){
   if([string]$pr.base.repo.full_name -cne $script:GfxRepo -or [string]$pr.head.repo.full_name -cne $script:GfxRepo){continue}
   if($pr.head.sha -notmatch '^[0-9a-f]{40}$'){throw 'Pull request collection contains a malformed head SHA.'}
   $null=$items.Add([pscustomobject][ordered]@{number=[int]$pr.number;state=[string]$pr.state;draft=[bool]$pr.draft;merged=($null -ne $pr.merged_at);baseBranch=[string]$pr.base.ref;headBranch=[string]$pr.head.ref;headSha=[string]$pr.head.sha;htmlUrl=[string]$pr.html_url;updatedAtUtc=[string]$pr.updated_at})
  }
  if($r.Count -lt $PerPage){break}
 }
 return [pscustomobject][ordered]@{repository=$script:GfxRepo;state=$State;count=$items.Count;truncated=($items.Count -ge ($PerPage*$script:GfxMaxPages));pullRequests=@($items.ToArray());capturedAtUtc=[DateTime]::UtcNow.ToString('o',[Globalization.CultureInfo]::InvariantCulture)}
}
function Get-GfxGitHubWorkflowRuns {
 [CmdletBinding()]param([Parameter(Mandatory=$true)][string]$CommitSha,[ValidateRange(1,100)][int]$PerPage=100)
 if($CommitSha -notmatch '^[0-9a-f]{40}$'){throw 'Workflow query requires a full lowercase 40-character commit SHA.'}
 $items=New-Object Collections.ArrayList;$total=$null
 for($page=1;$page -le $script:GfxMaxPages;$page++){
  $r=Invoke-GfxApiJson -Path 'actions/runs' -Query ("head_sha=$CommitSha&per_page=$PerPage&page=$page")
  if($null -eq $r.workflow_runs -or $r.workflow_runs -isnot [Array]){throw 'Workflow run response is malformed.'}
  $total=[int]$r.total_count
  foreach($run in $r.workflow_runs){
   if([string]$run.head_sha -cne $CommitSha){throw 'Actions API returned a run for a different commit SHA.'}
   if([long]$run.id -lt 1 -or $run.status -notin @('queued','in_progress','completed','requested','waiting','pending_request')){throw 'Workflow run metadata failed validation.'}
   $null=$items.Add([pscustomobject][ordered]@{runId=[long]$run.id;workflowId=[long]$run.workflow_id;runNumber=[int]$run.run_number;attempt=[int]$run.run_attempt;name=[string]$run.name;event=[string]$run.event;status=[string]$run.status;conclusion=[string]$run.conclusion;headSha=[string]$run.head_sha;headBranch=[string]$run.head_branch;createdAtUtc=[string]$run.created_at;updatedAtUtc=[string]$run.updated_at;htmlUrl=[string]$run.html_url})
  }
  if($r.workflow_runs.Count -lt $PerPage -or $items.Count -ge $total){break}
 }
 return [pscustomobject][ordered]@{repository=$script:GfxRepo;commitSha=$CommitSha;totalReported=$total;capturedCount=$items.Count;truncated=($null -ne $total -and $items.Count -lt $total -and $items.Count -ge ($PerPage*$script:GfxMaxPages));workflowRuns=@($items.ToArray());capturedAtUtc=[DateTime]::UtcNow.ToString('o',[Globalization.CultureInfo]::InvariantCulture)}
}
function Get-GfxGitHubRunArtifacts {
 [CmdletBinding()]param([Parameter(Mandatory=$true)][ValidateRange(1,9223372036854775807)][long]$RunId,[ValidateRange(1,100)][int]$PerPage=100)
 $items=New-Object Collections.ArrayList;$total=$null
 for($page=1;$page -le $script:GfxMaxPages;$page++){
  $r=Invoke-GfxApiJson -Path ('actions/runs/'+$RunId+'/artifacts') -Query ("per_page=$PerPage&page=$page")
  if($null -eq $r.artifacts -or $r.artifacts -isnot [Array]){throw 'Workflow artifact response is malformed.'}
  $total=[int]$r.total_count
  foreach($a in $r.artifacts){
   if([long]$a.id -lt 1 -or [long]$a.size_in_bytes -lt 0){throw 'Artifact metadata failed validation.'}
   $digest=[string]$a.digest
   if($digest -and $digest -notmatch '^sha256:[0-9a-f]{64}$'){throw 'Artifact digest has an unsupported format.'}
   $null=$items.Add([pscustomobject][ordered]@{artifactId=[long]$a.id;runId=$RunId;name=[string]$a.name;sizeBytes=[long]$a.size_in_bytes;expired=[bool]$a.expired;digest=$digest;createdAtUtc=[string]$a.created_at;expiresAtUtc=[string]$a.expires_at;archiveUrl=[string]$a.archive_download_url})
  }
  if($r.artifacts.Count -lt $PerPage -or $items.Count -ge $total){break}
 }
 return [pscustomobject][ordered]@{repository=$script:GfxRepo;runId=$RunId;totalReported=$total;capturedCount=$items.Count;truncated=($null -ne $total -and $items.Count -lt $total -and $items.Count -ge ($PerPage*$script:GfxMaxPages));artifacts=@($items.ToArray());capturedAtUtc=[DateTime]::UtcNow.ToString('o',[Globalization.CultureInfo]::InvariantCulture)}
}
function Get-GfxGitHubCommitEvidence {
 [CmdletBinding()]param([Parameter(Mandatory=$true)][string]$CommitSha)
 if($CommitSha -notmatch '^[0-9a-f]{40}$'){throw 'Commit evidence requires a full lowercase commit SHA.'}
 $repository=Get-GfxGitHubRepository;$commit=Get-GfxGitHubCommit -Ref $CommitSha;$runs=Get-GfxGitHubWorkflowRuns -CommitSha $CommitSha
 $allArtifacts=New-Object Collections.ArrayList
 foreach($run in $runs.workflowRuns){
  $result=Get-GfxGitHubRunArtifacts -RunId $run.runId
  foreach($artifact in $result.artifacts){$null=$allArtifacts.Add($artifact)}
 }
 $result=[pscustomobject][ordered]@{
  schemaVersion='sharnou.devagent.github-evidence/1';provider='github-rest';apiVersion=$script:GfxApiVersion
  repository=[pscustomobject][ordered]@{fullName=$repository.repository;repositoryId=$repository.repositoryId;defaultBranch=$repository.defaultBranch;visibility=$repository.visibility}
  capturedAtUtc=[DateTime]::UtcNow.ToString('o',[Globalization.CultureInfo]::InvariantCulture)
  commit=[pscustomobject][ordered]@{sha=$commit.sha;treeSha=$commit.treeSha;messageSha256=$commit.messageSha256;authorDateUtc=$commit.authorDateUtc;committerDateUtc=$commit.committerDateUtc}
  workflowRuns=@($runs.workflowRuns);artifacts=@($allArtifacts.ToArray());truncated=$runs.truncated
 }
 $validation=Test-GfxGitHubEvidenceObject -Evidence $result
 if(-not $validation.valid){throw ('Evidence snapshot failed self-validation: '+($validation.errors -join '; '))}
 return $result
}
function Get-GfxGitHubPullRequestEvidence {
 [CmdletBinding()]param([Parameter(Mandatory=$true)][ValidateRange(1,2147483647)][int]$PullRequestNumber)
 $pr=Get-GfxGitHubPullRequest -PullRequestNumber $PullRequestNumber
 $evidence=Get-GfxGitHubCommitEvidence -CommitSha $pr.headSha
 Add-Member -InputObject $evidence -NotePropertyName pullRequest -NotePropertyValue ([pscustomobject][ordered]@{number=$pr.number;state=$pr.state;draft=$pr.draft;merged=$pr.merged;baseBranch=$pr.baseBranch;headBranch=$pr.headBranch;baseSha=$pr.baseSha;headSha=$pr.headSha;htmlUrl=$pr.htmlUrl})
 $validation=Test-GfxGitHubEvidenceObject -Evidence $evidence
 if(-not $validation.valid){throw ('Pull request evidence failed self-validation: '+($validation.errors -join '; '))}
 return $evidence
}
function Test-GfxGitHubEvidenceObject {
 [CmdletBinding()]param([Parameter(Mandatory=$true)]$Evidence)
 $errors=New-Object Collections.ArrayList
 $required=@('schemaVersion','provider','apiVersion','repository','capturedAtUtc','commit','workflowRuns','artifacts','truncated')
 foreach($name in $required){if($null -eq $Evidence.PSObject.Properties[$name]){$null=$errors.Add("Evidence is missing '$name'.")}}
 if($Evidence.schemaVersion -cne 'sharnou.devagent.github-evidence/1'){$null=$errors.Add('Evidence schema version is invalid.')}
 if($Evidence.provider -cne 'github-rest' -or $Evidence.apiVersion -cne $script:GfxApiVersion){$null=$errors.Add('Evidence provider/API version is invalid.')}
 if($Evidence.repository.fullName -cne $script:GfxRepo -or [long]$Evidence.repository.repositoryId -lt 1){$null=$errors.Add('Evidence repository identity is invalid.')}
 if($Evidence.commit.sha -notmatch '^[0-9a-f]{40}$' -or $Evidence.commit.treeSha -notmatch '^[0-9a-f]{40}$' -or $Evidence.commit.messageSha256 -notmatch '^[0-9a-f]{64}$'){$null=$errors.Add('Evidence commit binding is invalid.')}
 if($Evidence.workflowRuns -isnot [Array] -or $Evidence.artifacts -isnot [Array]){$null=$errors.Add('Evidence workflowRuns/artifacts must be arrays.')}
 else{
  foreach($run in $Evidence.workflowRuns){if($run.headSha -cne $Evidence.commit.sha -or [long]$run.runId -lt 1){$null=$errors.Add('A workflow run is not bound to the evidence commit SHA.')}}
  foreach($artifact in $Evidence.artifacts){if([long]$artifact.artifactId -lt 1 -or [long]$artifact.runId -lt 1 -or [string]$artifact.digest -notmatch '^sha256:[0-9a-f]{64}$'){$null=$errors.Add('Artifact evidence lacks an identity or SHA-256 digest.')};if(-not(@($Evidence.workflowRuns|Where-Object{$_.runId -eq $artifact.runId}).Count -eq 1)){$null=$errors.Add('Artifact evidence is not bound to exactly one captured workflow run.')}}
 }
 if($Evidence.truncated -isnot [bool]){$null=$errors.Add('Evidence truncated flag must be Boolean.')}
 $time=[DateTimeOffset]::MinValue;if(-not[DateTimeOffset]::TryParse([string]$Evidence.capturedAtUtc,[ref]$time)){$null=$errors.Add('Evidence timestamp is invalid.')}
 if($null -ne $Evidence.PSObject.Properties['pullRequest'] -and $null -ne $Evidence.pullRequest){
  if([int]$Evidence.pullRequest.number -lt 1 -or $Evidence.pullRequest.headSha -cne $Evidence.commit.sha -or [string]::IsNullOrWhiteSpace([string]$Evidence.pullRequest.headBranch)){$null=$errors.Add('Pull request does not bind to the evidence commit.')}
 }
 return [pscustomobject][ordered]@{valid=($errors.Count -eq 0);errors=@($errors.ToArray());workflowRunCount=$(if($Evidence.workflowRuns -is [Array]){$Evidence.workflowRuns.Count}else{0});artifactCount=$(if($Evidence.artifacts -is [Array]){$Evidence.artifacts.Count}else{0})}
}
Export-ModuleMember -Function Get-GfxGitHubCredentialStatus,Set-GfxGitHubCredential,Remove-GfxGitHubCredential,Get-GfxGitHubRepository,Get-GfxGitHubBranch,Get-GfxGitHubCommit,Get-GfxGitHubFile,Get-GfxGitHubPullRequest,Get-GfxGitHubPullRequests,Get-GfxGitHubWorkflowRuns,Get-GfxGitHubRunArtifacts,Get-GfxGitHubCommitEvidence,Get-GfxGitHubPullRequestEvidence,Test-GfxGitHubEvidenceObject
