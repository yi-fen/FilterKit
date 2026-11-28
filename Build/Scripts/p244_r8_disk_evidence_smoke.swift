import Foundation
import Glibc

enum SmokeFailure: Error { case expectedRejection }
struct HelperPolicy {
 static func isAbsoluteCleanPath(_ s:String)->Bool { s.hasPrefix("/") && !s.contains("\0") && !s.split(separator:"/").contains("..") }
 static func isValidHash(_ s:String)->Bool { s.range(of:"^[0-9a-f]{64}$",options:.regularExpression) != nil }
 static func isValidCDHash(_ s:String)->Bool { s.range(of:"^[0-9a-f]{40}$",options:.regularExpression) != nil }
}
struct HelperInstallerArtifactDigest { let relativePath:String; let sha256:String }
struct HelperInstallerTransactionPlan { enum Action:Equatable { case install, upgrade, repin }; let jbRootPath:String; let action:Action }
struct HelperInstallerTransactionJournal:Equatable {
 enum State:Equatable { case artifactsVerified, previousReleasePreserved, staged }
 enum PendingOperation:Equatable { case preservePreviousRelease, stageRelease }
 enum Event { case preservePreviousRelease, stageRelease }
 let transactionID:UUID; let action:HelperInstallerTransactionPlan.Action; let releaseIdentifier:String; let generation:UInt64
 var state:State = .artifactsVerified; var pendingOperation:PendingOperation? = .stageRelease
 mutating func apply(_ e:Event)throws { switch e { case .preservePreviousRelease: state = .previousReleasePreserved; pendingOperation=nil; case .stageRelease: state = .staged; pendingOperation=nil } }
}
struct HelperInstallerDurableJournalStore {
 static var values:[UUID:HelperInstallerTransactionJournal]=[:]
 func save(_ v:HelperInstallerTransactionJournal)throws { Self.values[v.transactionID]=v }
 func load(transactionID:UUID)throws->HelperInstallerTransactionJournal { guard let v=Self.values[transactionID] else { throw SmokeFailure.expectedRejection }; return v }
}
struct HelperRootReleaseSet {
 enum Artifact:String,CaseIterable,Hashable { case executable, deploymentManifest, launchDaemon }
 struct Verified:Equatable { let releaseIdentifier:String; let generation:UInt64; let hashes:[Artifact:String]; let byteCounts:[Artifact:Int] }
 static let executablePath="usr/libexec/filterkit-helper", manifestPath="Library/FilterKit/Helper/Deployment.json", launchDaemonPath="Library/LaunchDaemons/cn.yfen.filterkit.helper.plist"
 func verify(bundle:HelperSignedProvisioningManifest.Payload,artifacts:[String:Data],expectedDigests:[HelperInstallerArtifactDigest])throws->Verified { let paths=[Self.executablePath,Self.manifestPath,Self.launchDaemonPath]; var h:[Artifact:String]=[:],c:[Artifact:Int]=[:]; for (a,p) in zip(Artifact.allCases,paths) { guard let d=artifacts[p] else { throw SmokeFailure.expectedRejection }; h[a]=SHA256Digest.hex(d); c[a]=d.count }; return Verified(releaseIdentifier:bundle.releaseIdentifier,generation:bundle.generation,hashes:h,byteCounts:c) }
}
struct HelperSignedProvisioningManifest:Decodable {
 struct Payload:Decodable { let jbRootPath:String; let releaseIdentifier:String; let generation:UInt64; let helperCDHash:String; let teamIdentifier:String? }
 let payload:Payload
}
struct HelperPreparedRootInstall { let plan:HelperInstallerTransactionPlan; let release:HelperRootReleaseSet.Verified; let provisioningEnvelopeSHA256:String; let provisioningEnvelopeData:Data; let initialJournal:HelperInstallerTransactionJournal }
struct HelperInstallerSharedTransactionLock { static func withExclusiveLock<T>(jbroot:String,_ body:()throws->T)throws->T { try body() } }
struct MachOSliceMetadata { let codeSignatureState:String="cdhash_extracted"; let codeSignatureTeamIdentifier:String?=nil; let cdHash:String?=nil }
struct MachOMetadataReader { func readSlices(data:Data)throws->[MachOSliceMetadata] { [MachOSliceMetadata()] } }

func check(_ condition:Bool,_ label:String,_ n:inout Int) { n += 1; if !condition { fputs("FAIL: \(label)\n",stderr); exit(1) }; print("PASS: \(label)") }
func mkdirp(_ p:String,_ mode:mode_t=0o700)throws { try FileManager.default.createDirectory(atPath:p,withIntermediateDirectories:true); _ = chmod(p,mode) }
func write(_ d:Data,_ p:String,_ mode:mode_t)throws { try d.write(to:URL(fileURLWithPath:p)); _ = chmod(p,mode) }
func artifactData()->[HelperRootReleaseSet.Artifact:Data] { [.executable:Data("binary-fixture".utf8),.deploymentManifest:Data("manifest-fixture".utf8),.launchDaemon:Data("plist-fixture".utf8)] }
func expected(_ data:[HelperRootReleaseSet.Artifact:Data])->[HelperRootReleaseSet.Artifact:String] { Dictionary(uniqueKeysWithValues:data.map{($0.key,SHA256Digest.hex($0.value))}) }
func fileName(_ a:HelperRootReleaseSet.Artifact)->String { switch a {case .executable:return "filterkit-helper";case .deploymentManifest:return "Deployment.json";case .launchDaemon:return "cn.yfen.filterkit.helper.plist"} }
func installFixture(root:String,relative:String,id:UUID,data:[HelperRootReleaseSet.Artifact:Data])throws->String { let dir=root+"/"+relative+"/"+id.uuidString.lowercased(); try mkdirp(dir); for a in HelperRootReleaseSet.Artifact.allCases { let mode:mode_t = a == .executable ? 0o755 : (a == .deploymentManifest ? 0o600 : 0o644); try write(data[a]!,dir+"/"+fileName(a),mode) }; return dir }
func rejected(_ body:()throws->Void)->Bool { do { try body(); return false } catch { return true } }

@main struct Main {
 static func main() throws {
  guard geteuid()==0 else { print("SKIP: requires root for root-owned fixture validation"); return }
  var n=0; let root="/root/p244-r8-\(UUID().uuidString.lowercased())"; try mkdirp(root,0o755); defer { try? FileManager.default.removeItem(atPath:root) }
  let data=artifactData(), hashes=expected(data), staged=try HelperInstallerStagedReleaseStore(jbRootPath:root), previous=try HelperInstallerPreviousReleaseStore(jbRootPath:root)
  let stagedBase=root+"/"+HelperInstallerStagedReleaseStore.relativeRootPath, previousBase=root+"/"+HelperInstallerPreviousReleaseStore.relativeRootPath
  try mkdirp(stagedBase); try mkdirp(previousBase)
  func stagedRead(_ id:UUID,_ h:[HelperRootReleaseSet.Artifact:String]=hashes)throws->[HelperRootReleaseSet.Artifact:Data] { try staged.loadVerifiedArtifactsForActivation(transactionID:id,expectedHashes:h) }
  func previousRead(_ id:UUID,_ h:[HelperRootReleaseSet.Artifact:String]=hashes)throws->[HelperRootReleaseSet.Artifact:Data] { try previous.loadVerifiedArtifactsForActivation(transactionID:id,expectedHashes:h) }
  let sid=UUID(); _ = try installFixture(root:root,relative:HelperInstallerStagedReleaseStore.relativeRootPath,id:sid,data:data)
  check(try stagedRead(sid)==data,"Staged loader reads exact three root-owned artifacts",&n)
  let pid=UUID(); _ = try installFixture(root:root,relative:HelperInstallerPreviousReleaseStore.relativeRootPath,id:pid,data:data)
  check(try previousRead(pid)==data,"Previous loader reads exact three root-owned artifacts",&n)
  check(rejected{_ = try stagedRead(UUID())},"Staged loader rejects missing transaction",&n)
  check(rejected{_ = try previousRead(UUID())},"Previous loader rejects missing backup",&n)
  check(rejected{_ = try stagedRead(sid,[.executable:hashes[.executable]!])},"Staged loader rejects incomplete expected hash inventory",&n)
  check(rejected{_ = try previousRead(pid,[.executable:hashes[.executable]!])},"Previous loader rejects incomplete expected hash inventory",&n)
  let tamperS=UUID(); let ts=try installFixture(root:root,relative:HelperInstallerStagedReleaseStore.relativeRootPath,id:tamperS,data:data); try write(Data("changed".utf8),ts+"/Deployment.json",0o600)
  check(rejected{_ = try stagedRead(tamperS)},"Staged loader rejects modified artifact bytes",&n)
  let tamperP=UUID(); let tp=try installFixture(root:root,relative:HelperInstallerPreviousReleaseStore.relativeRootPath,id:tamperP,data:data); try write(Data("changed".utf8),tp+"/Deployment.json",0o600)
  check(rejected{_ = try previousRead(tamperP)},"Previous loader rejects modified artifact bytes",&n)
  let missingS=UUID(); let ms=try installFixture(root:root,relative:HelperInstallerStagedReleaseStore.relativeRootPath,id:missingS,data:data); try FileManager.default.removeItem(atPath:ms+"/Deployment.json")
  check(rejected{_ = try stagedRead(missingS)},"Staged loader rejects missing member of three-file set",&n)
  let missingP=UUID(); let mp=try installFixture(root:root,relative:HelperInstallerPreviousReleaseStore.relativeRootPath,id:missingP,data:data); try FileManager.default.removeItem(atPath:mp+"/Deployment.json")
  check(rejected{_ = try previousRead(missingP)},"Previous loader rejects missing member of three-file set",&n)
  let extraS=UUID(); let es=try installFixture(root:root,relative:HelperInstallerStagedReleaseStore.relativeRootPath,id:extraS,data:data); try write(Data("x".utf8),es+"/unexpected",0o600)
  check(rejected{_ = try stagedRead(extraS)},"Staged loader rejects unexpected directory entry",&n)
  let extraP=UUID(); let ep=try installFixture(root:root,relative:HelperInstallerPreviousReleaseStore.relativeRootPath,id:extraP,data:data); try write(Data("x".utf8),ep+"/unexpected",0o600)
  check(rejected{_ = try previousRead(extraP)},"Previous loader rejects unexpected directory entry",&n)
  let symS=UUID(); let ss=try installFixture(root:root,relative:HelperInstallerStagedReleaseStore.relativeRootPath,id:symS,data:data); try FileManager.default.removeItem(atPath:ss+"/Deployment.json"); try FileManager.default.createSymbolicLink(atPath:ss+"/Deployment.json",withDestinationPath:"/etc/passwd")
  check(rejected{_ = try stagedRead(symS)},"Staged loader rejects symlink artifact",&n)
  let symP=UUID(); let sp=try installFixture(root:root,relative:HelperInstallerPreviousReleaseStore.relativeRootPath,id:symP,data:data); try FileManager.default.removeItem(atPath:sp+"/Deployment.json"); try FileManager.default.createSymbolicLink(atPath:sp+"/Deployment.json",withDestinationPath:"/etc/passwd")
  check(rejected{_ = try previousRead(symP)},"Previous loader rejects symlink artifact",&n)
  let hardS=UUID(); let hs=try installFixture(root:root,relative:HelperInstallerStagedReleaseStore.relativeRootPath,id:hardS,data:data); try FileManager.default.linkItem(atPath:hs+"/Deployment.json",toPath:hs+"/hardlink")
  check(rejected{_ = try stagedRead(hardS)},"Staged loader rejects hard-linked artifact",&n)
  let hardP=UUID(); let hp=try installFixture(root:root,relative:HelperInstallerPreviousReleaseStore.relativeRootPath,id:hardP,data:data); try FileManager.default.linkItem(atPath:hp+"/Deployment.json",toPath:hp+"/hardlink")
  check(rejected{_ = try previousRead(hardP)},"Previous loader rejects hard-linked artifact",&n)
  let modeS=UUID(); let mmS=try installFixture(root:root,relative:HelperInstallerStagedReleaseStore.relativeRootPath,id:modeS,data:data); _ = chmod(mmS+"/Deployment.json",0o644)
  check(rejected{_ = try stagedRead(modeS)},"Staged loader rejects incorrect artifact mode",&n)
  let modeP=UUID(); let mmP=try installFixture(root:root,relative:HelperInstallerPreviousReleaseStore.relativeRootPath,id:modeP,data:data); _ = chmod(mmP+"/Deployment.json",0o644)
  check(rejected{_ = try previousRead(modeP)},"Previous loader rejects incorrect artifact mode",&n)
  check(rejected{_ = try stagedRead(sid,Dictionary(uniqueKeysWithValues:hashes.map{($0.key,String(repeating:"0",count:64))}))},"Staged loader rejects expected-hash mismatch",&n)
  check(rejected{_ = try previousRead(pid,Dictionary(uniqueKeysWithValues:hashes.map{($0.key,String(repeating:"0",count:64))}))},"Previous loader rejects expected-hash mismatch",&n)
  let dirModeS=UUID(); let dmS=try installFixture(root:root,relative:HelperInstallerStagedReleaseStore.relativeRootPath,id:dirModeS,data:data); _ = chmod(dmS,0o777)
  check(rejected{_ = try stagedRead(dirModeS)},"Staged loader rejects group/world-writable transaction directory",&n)
  let dirModeP=UUID(); let dmP=try installFixture(root:root,relative:HelperInstallerPreviousReleaseStore.relativeRootPath,id:dirModeP,data:data); _ = chmod(dmP,0o777)
  check(rejected{_ = try previousRead(dirModeP)},"Previous loader rejects group/world-writable backup directory",&n)
  let ownerS=UUID(); let owS=try installFixture(root:root,relative:HelperInstallerStagedReleaseStore.relativeRootPath,id:ownerS,data:data); _ = chown((owS+"/Deployment.json"),65534,65534)
  check(rejected{_ = try stagedRead(ownerS)},"Staged loader rejects non-root-owned artifact",&n)
  let ownerP=UUID(); let owP=try installFixture(root:root,relative:HelperInstallerPreviousReleaseStore.relativeRootPath,id:ownerP,data:data); _ = chown((owP+"/Deployment.json"),65534,65534)
  check(rejected{_ = try previousRead(ownerP)},"Previous loader rejects non-root-owned artifact",&n)
  let dirLinkS=UUID(); let realDir=try installFixture(root:root,relative:HelperInstallerStagedReleaseStore.relativeRootPath,id:dirLinkS,data:data)
  let heldDir=realDir+"-real"; try FileManager.default.moveItem(atPath:realDir,toPath:heldDir)
  try FileManager.default.createSymbolicLink(atPath:realDir,withDestinationPath:heldDir)
  check(rejected{_ = try staged.loadVerifiedArtifactsForActivation(transactionID:dirLinkS,expectedHashes:hashes)},"Staged loader rejects symlink transaction directory",&n)
  print("RESULT: \(n)/25 passed")
 }
}
