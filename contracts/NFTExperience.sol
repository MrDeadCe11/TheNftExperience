// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "hardhat/console.sol";
/**
 * this contract will mint a child NFT to any Parent ERC721.  this NFT is soulbound to the whichever Token it is minted to
 * and assigns a level to that NFT according to how much experience the child NFT contains.
 */

contract NFTExperience is
    ERC721,
    ERC721Enumerable,
    ERC721URIStorage,
    ERC721Burnable,
    Ownable,
    IERC721Receiver
{

    event ChildTransferedToParent(
        address indexed _toContract,
        uint256 indexed _toTokenId,
        uint256 _tokenId
    );
    struct TokenOwner {
        address tokenOwner;
        uint256 parentTokenId;
    }

    // return this.rootOwnerOf.selector ^ this.rootOwnerOfChild.selector ^
    //   this.tokenOwnerOf.selector ^ this.ownerOfChild.selector;
    bytes32 ERC998_MAGIC_VALUE = uint256ToBytes32(0xcd740db5);

    // tokenId => token owner
    mapping(uint256 => TokenOwner) internal tokenIdToTokenOwner;

    // root token owner address => (tokenId => approved address)
    mapping(address => mapping(uint256 => address))
        internal rootOwnerAndTokenIdToApprovedAddress;

    // token owner address => token count
    mapping(address => uint256) internal tokenOwnerToTokenCount;

    // token owner => (operator address => bool)
    mapping(address => mapping(address => bool)) internal tokenOwnerToOperators;

    // parent address => (parent tokenId => array of child tokenIds)
    mapping(address => mapping(uint256 => uint256[]))
        private parentToChildTokenIds;

    // tokenId => position in childTokens array
    mapping(uint256 => uint256) private tokenIdToChildTokenIdsIndex;

    using Counters for Counters.Counter;

    Counters.Counter private _tokenIdCounter;

    constructor() ERC721("CharacterSheet", "CHRS") {}

    function createCharacterSheet(
        address _tokenContractAddress,
        uint256 _toTokenId,
        string memory uri
    ) public onlyOwner {
        //TODO make mintable to an erc721 token
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        _safeMint(address(this), tokenId);
        _setTokenURI(tokenId, uri);
        this.transferToParent(
            address(this),
            _tokenContractAddress,
            _toTokenId,
            tokenId,
            ""
        );
        emit ChildTransferedToParent(_tokenContractAddress, _toTokenId, tokenId);
    }

    // The following functions are overrides required by Solidity.

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function _burn(
        uint256 tokenId
    ) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
    }

    function tokenURI(
        uint256 tokenId
    ) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC721, ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    // erc998 functions
    function isContract(address _addr) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(_addr)
        }
        return size > 0;
    }

    function _tokenOwnerOf(
        uint256 _tokenId
    )
        internal
        view
        returns (address tokenOwner, uint256 parentTokenId, bool isParent)
    {
        tokenOwner = tokenIdToTokenOwner[_tokenId].tokenOwner;
        require(tokenOwner != address(0));
        parentTokenId = tokenIdToTokenOwner[_tokenId].parentTokenId;
        if (parentTokenId > 0) {
            isParent = true;
            parentTokenId--;
        } else {
            isParent = false;
        }
        return (tokenOwner, parentTokenId, isParent);
    }

    function tokenOwnerOf(
        uint256 _tokenId
    )
        external
        view
        returns (bytes32 tokenOwner, uint256 parentTokenId, bool isParent)
    {
        address tokenOwnerAddress = tokenIdToTokenOwner[_tokenId].tokenOwner;
        require(tokenOwnerAddress != address(0));
        parentTokenId = tokenIdToTokenOwner[_tokenId].parentTokenId;
        if (parentTokenId > 0) {
            isParent = true;
            parentTokenId--;
        } else {
            isParent = false;
        }
        return (
            (ERC998_MAGIC_VALUE << 224) | addressToBytes32(tokenOwnerAddress),
            parentTokenId,
            isParent
        );
    }

    function rootOwnerOf(
        uint256 _tokenId
    ) public view returns (bytes32 rootOwner) {
        address rootOwnerAddress = tokenIdToTokenOwner[_tokenId].tokenOwner;
        require(rootOwnerAddress != address(0));
        uint256 parentTokenId = tokenIdToTokenOwner[_tokenId].parentTokenId;
        bool isParent = parentTokenId > 0;
        parentTokenId--;
        bytes memory _data;
        bool callSuccess;

        if ((rootOwnerAddress == address(this))) {
            do {
                if (isParent == false) {
                    // Case 1: Token owner is this contract and no token.
                    // This case should not happen.
                    return
                        (ERC998_MAGIC_VALUE << 224) |
                        addressToBytes32(rootOwnerAddress);
                } else {
                    // Case 2: Token owner is this contract and token
                    (rootOwnerAddress, parentTokenId, isParent) = _tokenOwnerOf(
                        parentTokenId
                    );
                }
            } while (rootOwnerAddress == address(this));
            _tokenId = parentTokenId;
        }

        if (isParent == false) {
            // success if this token is owned by a top-down token
            // 0xed81cdda == rootOwnerOfChild(address, uint256)
            _data = abi.encodeWithSelector(0xed81cdda, address(this), _tokenId);
            assembly {
                callSuccess := staticcall(
                    gas(),
                    rootOwnerAddress,
                    add(_data, 0x20),
                    mload(_data),
                    _data,
                    0x20
                )
                if callSuccess {
                    rootOwner := mload(_data)
                }
            }
            if (callSuccess == true && rootOwner >> 224 == ERC998_MAGIC_VALUE) {
                // Case 3: Token owner is top-down composable
                return rootOwner;
            } else {
                // Case 4: Token owner is an unknown contract
                // Or
                // Case 5: Token owner is a user
                return
                    (ERC998_MAGIC_VALUE << 224) |
                    addressToBytes32(rootOwnerAddress);
            }
        } else {
            // 0x43a61a8e == rootOwnerOf(uint256)
            _data = abi.encodeWithSelector(0x43a61a8e, parentTokenId);
            assembly {
                callSuccess := staticcall(
                    gas(),
                    rootOwnerAddress,
                    add(_data, 0x20),
                    mload(_data),
                    _data,
                    0x20
                )
                if callSuccess {
                    rootOwner := mload(_data)
                }
            }
            if (callSuccess == true && rootOwner >> 224 == ERC998_MAGIC_VALUE) {
                // Case 6: Token owner is a bottom-up composable
                // Or
                // Case 2: Token owner is top-down composable
                return rootOwner;
            } else {
                // token owner is ERC721
                address childContract = rootOwnerAddress;
                //0x6352211e == "ownerOf(uint256)"
                _data = abi.encodeWithSelector(0x6352211e, parentTokenId);
                assembly {
                    callSuccess := staticcall(
                        gas(),
                        rootOwnerAddress,
                        add(_data, 0x20),
                        mload(_data),
                        _data,
                        0x20
                    )
                    if callSuccess {
                        rootOwnerAddress := mload(_data)
                    }
                }
                require(callSuccess, "Call to ownerOf failed");

                // 0xed81cdda == rootOwnerOfChild(address,uint256)
                _data = abi.encodeWithSelector(
                    0xed81cdda,
                    childContract,
                    parentTokenId
                );
                assembly {
                    callSuccess := staticcall(
                        gas(),
                        rootOwnerAddress,
                        add(_data, 0x20),
                        mload(_data),
                        _data,
                        0x20
                    )
                    if callSuccess {
                        rootOwner := mload(_data)
                    }
                }
                if (
                    callSuccess == true &&
                    rootOwner >> 224 == ERC998_MAGIC_VALUE
                ) {
                    // Case 7: Token owner is ERC721 token owned by top-down token
                    return rootOwner;
                } else {
                    // Case 8: Token owner is ERC721 token owned by unknown contract
                    // Or
                    // Case 9: Token owner is ERC721 token owned by user
                    return
                        (ERC998_MAGIC_VALUE << 224) |
                        addressToBytes32(rootOwnerAddress);
                }
            }
        }
    }

    /**
     * * In a bottom-up composable authentication to transfer etc. is done by getting the rootOwner by finding the parent token
     * and then the parent token of that one until a final owner address is found.  If the msg.sender is the rootOwner or is
     * approved by the rootOwner then msg.sender is authenticated and the action can occur.
     * This enables the owner of the top-most parent of a tree of composables to call any method on child composables.
     */
    // returns the root owner at the top of the tree of composables
    function ownerOf(
        uint256 _tokenId
    ) public view override(ERC721, IERC721) returns (address) {
        address tokenOwner = tokenIdToTokenOwner[_tokenId].tokenOwner;
        require(tokenOwner != address(0));
        return tokenOwner;
    }

    /** conversion functions */
    function uint256ToBytes32(uint256 x) public pure returns (bytes32 b) {
        b = bytes32(x);
    }

    function addressToBytes32(
        address _address
    ) public pure returns (bytes32 _bytes) {
        _bytes = bytes32(uint256(uint160(_address)));
    }
    function bytes32ToAddress (bytes32 _input) public pure returns(address){
        return address(uint160(uint256(_input)));
    }
    function removeChild(
        address _fromContract,
        uint256 _fromTokenId,
        uint256 _tokenId
    ) internal {
        uint256 childTokenIndex = tokenIdToChildTokenIdsIndex[_tokenId];
        uint256 lastChildTokenIndex = parentToChildTokenIds[_fromContract][
            _fromTokenId
        ].length - 1;
        uint256 lastChildTokenId = parentToChildTokenIds[_fromContract][
            _fromTokenId
        ][lastChildTokenIndex];

        if (_tokenId != lastChildTokenId) {
            parentToChildTokenIds[_fromContract][_fromTokenId][
                childTokenIndex
            ] = lastChildTokenId;
            tokenIdToChildTokenIdsIndex[lastChildTokenId] = childTokenIndex;
        }
        parentToChildTokenIds[_fromContract][_fromTokenId].pop;
    }

    function authenticateAndClearApproval(uint256 _tokenId) private {
        address rootOwner = bytes32ToAddress(rootOwnerOf(_tokenId));
        address approvedAddress = rootOwnerAndTokenIdToApprovedAddress[
            rootOwner
        ][_tokenId];
        require(
            rootOwner == msg.sender ||
                tokenOwnerToOperators[rootOwner][msg.sender] ||
                approvedAddress == msg.sender
        );

        // clear approval
        if (approvedAddress != address(0)) {
            delete rootOwnerAndTokenIdToApprovedAddress[rootOwner][_tokenId];
            emit Approval(rootOwner, address(0), _tokenId);
        }
    }

    /**
     * transfers a child nft from this contract to a parent nft
     * @param _from: address sending the child composable
     * @param _toContract: contract of parent nft the child composable
     * @param _toTokenId: token id of parent nft
     * @param _tokenId: child being transfered
     * @param _data: optional data
     */
    function transferToParent(
        address _from,
        address _toContract,
        uint256 _toTokenId,
        uint256 _tokenId,
        bytes calldata _data
    ) external {
        require(_from != address(0));
        require(tokenIdToTokenOwner[_tokenId].tokenOwner == _from);
        require(_toContract != address(0));
        require(
            tokenIdToTokenOwner[_tokenId].parentTokenId == 0,
            "Cannot transfer from address when owned by a token."
        );
        address approvedAddress = rootOwnerAndTokenIdToApprovedAddress[_from][
            _tokenId
        ];
        if (msg.sender != _from) {
            bytes32 rootOwner;
            bool callSuccess;
            // 0xed81cdda == rootOwnerOfChild(address,uint256)
            bytes memory _calldata = abi.encodeWithSelector(
                0xed81cdda,
                address(this),
                _tokenId
            );
            assembly {
                callSuccess := staticcall(
                    gas(),
                    _from,
                    add(_calldata, 0x20),
                    mload(_calldata),
                    _calldata,
                    0x20
                )
                if callSuccess {
                    rootOwner := mload(_calldata)
                }
            }
            if (callSuccess == true) {
                require(
                    rootOwner >> 224 != ERC998_MAGIC_VALUE,
                    "Token is child of other top down composable"
                );
            }
            require(
                tokenOwnerToOperators[_from][msg.sender] ||
                    approvedAddress == msg.sender
            );
        }

        // clear approval
        if (approvedAddress != address(0)) {
            delete rootOwnerAndTokenIdToApprovedAddress[_from][_tokenId];
            emit Approval(_from, address(0), _tokenId);
        }

        // remove and transfer token
        if (_from != _toContract) {
            assert(tokenOwnerToTokenCount[_from] > 0);
            tokenOwnerToTokenCount[_from]--;
            tokenOwnerToTokenCount[_toContract]++;
        }
        TokenOwner memory parentToken = TokenOwner(
            _toContract,
            _toTokenId++
        );
        tokenIdToTokenOwner[_tokenId] = parentToken;
        uint256 index = parentToChildTokenIds[_toContract][_toTokenId].length;
        parentToChildTokenIds[_toContract][_toTokenId].push(_tokenId);
        tokenIdToChildTokenIdsIndex[_tokenId] = index;

        require(
            ERC721(_toContract).ownerOf(_toTokenId) != address(0),
            "_toTokenId does not exist"
        );

        emit Transfer(_from, _toContract, _tokenId);
        emit ChildTransferedToParent(_toContract, _toTokenId, _tokenId);
    }

    /**
     * @dev transfers a child nft as child from one nft to another nft
     * @param _fromContract: contract that currently owns the nft that owns the nft being transfered.
     * @param _fromTokenId: the token id of the token that owns the child nft
     * @param _toContract: the contract that child nft is being tranfered to
     * @param _toTokenId: the token id of the nft the child nft is being transfered to.
     * @param _tokenId: the token ID of the child nft
     * @param _data data: optional data
     */
    function transferAsChild(
        address _fromContract,
        uint256 _fromTokenId,
        address _toContract,
        uint256 _toTokenId,
        uint256 _tokenId,
        bytes calldata _data
    ) external {
        require(tokenIdToTokenOwner[_tokenId].tokenOwner == _fromContract);
        require(_toContract != address(0));
        uint256 parentTokenId = tokenIdToTokenOwner[_tokenId].parentTokenId;
        require(parentTokenId > 0, "No parent token to transfer from.");
        require(parentTokenId - 1 == _fromTokenId);
        address rootOwner = bytes32ToAddress(rootOwnerOf(_tokenId));
        address approvedAddress = rootOwnerAndTokenIdToApprovedAddress[
            rootOwner
        ][_tokenId];
        require(
            rootOwner == msg.sender ||
                tokenOwnerToOperators[rootOwner][msg.sender] ||
                approvedAddress == msg.sender
        );
        // clear approval
        if (approvedAddress != address(0)) {
            delete rootOwnerAndTokenIdToApprovedAddress[rootOwner][_tokenId];
            emit Approval(rootOwner, address(0), _tokenId);
        }

        // remove and transfer token
        if (_fromContract != _toContract) {
            assert(tokenOwnerToTokenCount[_fromContract] > 0);
            tokenOwnerToTokenCount[_fromContract]--;
            tokenOwnerToTokenCount[_toContract]++;
        }

        TokenOwner memory parentToken = TokenOwner(_toContract, _toTokenId);
        tokenIdToTokenOwner[_tokenId] = parentToken;

        removeChild(_fromContract, _fromTokenId, _tokenId);

        //add to parentToChildTokenIds
        uint256 index = parentToChildTokenIds[_toContract][_toTokenId].length;
        parentToChildTokenIds[_toContract][_toTokenId].push(_tokenId);
        tokenIdToChildTokenIdsIndex[_tokenId] = index;

        require(
            ERC721(_toContract).ownerOf(_toTokenId) != address(0),
            "_toTokenId does not exist"
        );

        emit Transfer(_fromContract, _toContract, _tokenId);
        emit ChildTransferedToParent(_toContract, _toTokenId, _tokenId);
    }

    /**
     * @dev transfers an NFT to a EOA or Contract.  cannot transfer to or from another NFT
     *@param _from: 
     *@param _to: 
     @param _tokenId:
     */
    function _transferFrom(
        address _from,
        address _to,
        uint256 _tokenId
    ) internal {
        require(_from != address(0));
        require(tokenIdToTokenOwner[_tokenId].tokenOwner == _from);
        require(
            tokenIdToTokenOwner[_tokenId].parentTokenId == 0,
            "Cannot transfer from address when owned by a token."
        );
        require(_to != address(0));
        address approvedAddress = rootOwnerAndTokenIdToApprovedAddress[_from][
            _tokenId
        ];
        if (msg.sender != _from) {
            bytes32 rootOwner;
            bool callSuccess;
            // 0xed81cdda == rootOwnerOfChild(address,uint256)
            bytes memory _calldata = abi.encodeWithSelector(
                0xed81cdda,
                address(this),
                _tokenId
            );
            assembly {
                callSuccess := staticcall(
                    gas(),
                    _from,
                    add(_calldata, 0x20),
                    mload(_calldata),
                    _calldata,
                    0x20
                )
                if callSuccess {
                    rootOwner := mload(_calldata)
                }
            }
            if (callSuccess == true) {
                require(
                    rootOwner >> 224 != ERC998_MAGIC_VALUE,
                    "Token is child of other top down composable"
                );
            }
            require(
                tokenOwnerToOperators[_from][msg.sender] ||
                    approvedAddress == msg.sender
            );
        }

        // clear approval
        if (approvedAddress != address(0)) {
            delete rootOwnerAndTokenIdToApprovedAddress[_from][_tokenId];
            emit Approval(_from, address(0), _tokenId);
        }

        // remove and transfer token
        if (_from != _to) {
            assert(tokenOwnerToTokenCount[_from] > 0);
            tokenOwnerToTokenCount[_from]--;
            tokenIdToTokenOwner[_tokenId].tokenOwner = _to;
            tokenOwnerToTokenCount[_to]++;
        }
        emit Transfer(_from, _to, _tokenId);
    }

    /**
     * @dev override of openzeppelin transferFrom
     */
    function transferFrom(
        address _from,
        address _to,
        uint256 _tokenId
    ) public override(ERC721, IERC721) {
        _transferFrom(_from, _to, _tokenId);
    }

    /**
     * @dev override of openzeppelin safeTransferFrom
     */
    function safeTransferFrom(
        address _from,
        address _to,
        uint256 _tokenId
    ) public override(ERC721, IERC721) {
        _transferFrom(_from, _to, _tokenId);
    }

    // function safeTransferFrom(
    //     address _from,
    //     address _to,
    //     uint256 _tokenId,
    //     bytes _data
    // ) external override {
    //     _transferFrom(_from, _to, _tokenId);
    //     if (isContract(_to)) {
    //       require(_checkOnERC721Received(_from, _to, _tokenId, ""), "ERC721: transfer to non ERC721Receiver implementer");
    //     }
    // }

    function totalChildTokens(
        address _parentContract,
        uint256 _parentTokenId
    ) public view returns (uint256) {
        return parentToChildTokenIds[_parentContract][_parentTokenId].length;
    }

    function childTokenByIndex(
        address _parentContract,
        uint256 _parentTokenId,
        uint256 _index
    ) public view returns (uint256) {
        require(
            parentToChildTokenIds[_parentContract][_parentTokenId].length >
                _index
        );
        return parentToChildTokenIds[_parentContract][_parentTokenId][_index];
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external override returns (bytes4) {}
}
