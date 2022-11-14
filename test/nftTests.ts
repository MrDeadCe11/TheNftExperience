import { expect, assert } from "chai";
import { ethers } from "hardhat";
import { BigNumber, Contract, Signer} from "ethers";

describe("ERC998TopDownComposableEnumerable", function () {
  let owner: Signer, addr1: Signer, addr2: Signer;
  let addresses: Signer[];
  let erc998: Contract;
  let erc721: Contract;
  const testUri: string =
    "ipfs://bafybeihkoviema7g3gxyt6la7vd5ho32ictqbilu3wnlo3rs7ewhnp7lly/";
  let tokenCounter: any = 0;
  let tokensById = [];
  before(async () => {
    const ERC998TopDownComposableEnumerable = await ethers.getContractFactory(
      "ERC998TopDownComposableEnumerable"
    );
    [owner, addr1, addr2, ...addresses] = await ethers.getSigners();
    erc998 = await ERC998TopDownComposableEnumerable.deploy();
    await erc998.deployed();


    const CustomERC721 = await ethers.getContractFactory("CustomERC721");
    [owner, addr1, addr2, ...addresses] = await ethers.getSigners();
    erc721 = await CustomERC721.deploy();
    await erc721.deployed();

  });

  it("should mint a parentNFT and a childNFT to the owner address", async function () {
    //mint parent
    const txp = await erc998
      .mintParent(owner.getAddress(), testUri)
      .catch((err: Error) => console.log("PARENT MINT ERROR", err));

    //mint child
    const txc = await erc998
      .mintChild(tokenCounter, testUri)
      .catch((err: Error) => console.log("CHILD MINT ERROR", err));
    const parentId = tokenCounter;
    tokensById.push({ parent0: parentId });
    const promiseP = await txp.wait().then((res: Response) => tokenCounter++);
    const childId = tokenCounter;
    tokensById.push({ child0: childId });
    const promiseC = await txc.wait().then((res: Response) => tokenCounter++);

    const parentOwner = await erc998.ownerOf(parentId);
    const childOwner = await erc998.ownerOf(childId);
    console.log(
      "PARENT OWNER",
      parentOwner,
      "CHILD OWNER",
      childOwner,
      parentId,
      childId
    );
    //promiseP.events[0].args.to;
    assert((parentOwner && childOwner) === owner.getAddress());
  });

  it("should mint a child and parent nft to addr1", async function () {
    //store parentCounter
    const parentId = tokenCounter;
    tokensById.push({ parent1: parentId });
    //mint parent
    const txp = await erc998
      .mintParent(addr1.getAddress(), testUri)
      .catch((err: Error) => console.log("PARENT MINT ERROR", err));

    //mint child
    const txc = await erc998
      .mintChild(parentId, testUri)
      .catch((err: Error) => console.log("CHILD MINT ERROR", err));

    const promiseP = await txp.wait().then((res: Response) => tokenCounter++);
    const childId = tokenCounter;
    tokensById.push({ child1: childId });
    const promiseC = await txc.wait().then((res: Response) => tokenCounter++);

    const parentOwner = await erc998.ownerOf(parentId);
    const childOwner = await erc998.ownerOf(childId);
    console.log(
      "PARENT OWNER",
      parentOwner,
      "CHILD OWNER",
      childOwner,
      parentId,
      childId
    );
    //promiseP.events[0].args.to;
    assert((parentOwner && childOwner) === addr1.getAddress());
  });

  it("should return the number nft's owned by an address(owner)", async function () {
    const tx = await erc998.balanceOf(owner.getAddress());

    assert(tx.toNumber() === 2, "address holds incorrect number of tokens");
  });

  it("should return the root owner of owner of child0 (owner account)", async function () {
    const ownerOfParent = await erc998.addressOfRootOwner(erc998.getAddress(), 1);
    assert(ownerOfParent === owner.getAddress());
  });

  it("should return the number nft's owned by an address(addr1)", async function () {
    const tx = await erc998.balanceOf(addr1.getAddress());

    assert(tx.toNumber() === 2, "address holds incorrect number of tokens");
  });

  it("should transfer child token 0 from owner to parent nft(parent 1) owned by address 1", async function () {
    //approve(current owner address, token to be transfered)
    const approve = await erc998
      .approve(owner.getAddress(), 1)
      .catch((err: Error) => console.log("approval error", err));
    //safeTransferFrom(current Owner wallet Address, address of contract that minted ChildNFT, tokenid of ChildNFT, tokenId of ParentNFT)
  
    const tx = await erc998[`safeTransferFrom(address,address,uint256,bytes)`](
      owner.getAddress(),
      erc998.address,
      1,
      2
    ).catch((err: Error) => console.log("add child error", err));
      
    const promise = await tx.wait();
    const ownerOf1 = await erc998.rootOwnerOf(1);
    const ownerof2 = await erc998.ownerOf(2);
    console.log("ownerOf1", ownerOf1, "ownerof2", ownerof2);
    assert(ownerOf1.slice() === ownerof2, "token not transfered");
  });

  it("owner should only own 1 nft", async function () {
    const tx = await erc998
      .balanceOf(owner.getAddress())
      .catch((err: Error) => console.log(err));
    assert(tx.toNumber() === 2);
  });

  // it("should NOT transfer ownership of childNFT from owner to the ownerNFT", async function () {
  //   const tx = await erc998[
  //     `safeTransferFrom(address,address,uint256,bytes)`
  //   ](owner.address, erc998.address, 1, 0).catch((err) =>
  //     console.log(err)
  //   );
  //   const promise = await tx.wait();
  //   console.log(promise.events[0]);
  //   assert(0 === 0);
  // });
});
