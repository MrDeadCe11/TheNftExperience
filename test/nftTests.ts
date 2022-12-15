import { ChildTransferedToParentEvent } from './../typechain-types/contracts/NFTExperience';
import { CharacterSheetInterface } from './../typechain-types/contracts/CharacterSheet';
import { expect, assert } from "chai";
import { ethers } from "hardhat";
import { BigNumber, Contract, Signer, Event} from "ethers";
import { checkPrime } from 'crypto';

describe("CharacterSheet", function () {
  let owner: Signer, addr1: Signer, addr2: Signer;
  let addresses: Signer[];
  let characterSheet: Contract;
  let erc721: Contract;
  let testNft;
  let testCharacterSheet: BigNumber;
  const testUri: string =
    "ipfs://bafybeihkoviema7g3gxyt6la7vd5ho32ictqbilu3wnlo3rs7ewhnp7lly/";

  beforeEach(async () => {
    
    [owner, addr1, addr2, ...addresses] = await ethers.getSigners();

    const testNft = await ethers.getContractFactory("TestNft");
    const CharacterSheet = await ethers.getContractFactory(
      "CharacterSheet"
    );

    characterSheet = await CharacterSheet.deploy();
    await characterSheet.deployed();


    const CustomERC721 = await ethers.getContractFactory("TestNft");
    erc721 = await CustomERC721.deploy();
    await erc721.deployed();

  });
  it("should mint a testNFT to the owner address", async function (){
    let erc721TokenId;
    try{
      const txp = await erc721
        .safeMint(owner.getAddress())
        const promise = await txp.wait();
        const event = promise.events.filter((e:any)=> {
        return   e.event.includes("Transfer");
        })[0];
        erc721TokenId = event.args.tokenId.toNumber();
      } catch (err){
        console.error(err);  
      }
      expect(await erc721.ownerOf(erc721TokenId)).to.equal(await owner.getAddress());
  })
  
  it("should create a character sheet correctly", async function () {
    //mint parent
    let erc721TokenId, erc998TokenId;
    try{
    const txp = await erc721
      .safeMint(owner.getAddress())
      const promise = await txp.wait();
      const event = promise.events.filter((e:any)=> {
      return   e.event.includes("Transfer");
      })[0];
      erc721TokenId = event.args.tokenId.toNumber();
      console.log("721 TOKEN ID: ", erc721TokenId);
    } catch (err){
      console.error(err);  
    }
   

    expect(await erc721.ownerOf(erc721TokenId)).to.equal(await owner.getAddress());
    //mint child to parent  
    try{
    const txc = await characterSheet
      .createCharacterSheet(erc721.address, erc721TokenId, testUri).catch((err: any)=> console.error(err));
      const charPromise = await txc.wait();
      const event = charPromise.events.filter((e: any)=> e.event.includes("ChildTransferedToParent"));
      erc998TokenId = event[0].args._tokenId.toNumber();
    } catch (err){
      console.error(err);
    }

    const parentOwner = await erc721.ownerOf(erc721TokenId);
    const childOwner = await characterSheet.rootOwnerOfReturnAddress(erc998TokenId);
    console.log("CHILD OWNER: ",childOwner);
    console.log(
      "PARENT OWNER",
      parentOwner,
      "CHILD OWNER",
      childOwner
    );
    //promiseP.events[0].args.to;
    //assert((parentOwner && childOwner) === await owner.getAddress());
    expect(parentOwner).to.equal(childOwner);
  });
});