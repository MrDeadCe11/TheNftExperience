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


interface IERC998ERC721BottomUp {
    event TransferToParent(address indexed _toContract, uint256 indexed _toTokenId, uint256 _tokenId);
    event TransferFromParent(address indexed _fromContract, uint256 indexed _fromTokenId, uint256 _tokenId);


    function rootOwnerOf(uint256 _tokenId) external view returns (bytes32 rootOwner);

    /**
    * The tokenOwnerOf function gets the owner of the _tokenId which can be a user address or another ERC721 token.
    * The tokenOwner address return value can be either a user address or an ERC721 contract address.
    * If the tokenOwner address is a user address then parentTokenId will be 0 and should not be used or considered.
    * If tokenOwner address is a user address then isParent is false, otherwise isChild is true, which means that
    * tokenOwner is an ERC721 contract address and _tokenId is a child of tokenOwner and parentTokenId.
    */
    function tokenOwnerOf(uint256 _tokenId) external view returns (bytes32 tokenOwner, uint256 parentTokenId, bool isParent);

    // Transfers _tokenId as a child to _toContract and _toTokenId
    function transferToParent(address _from, address _toContract, uint256 _toTokenId, uint256 _tokenId, bytes memory _data) external;
    // Transfers _tokenId from a parent ERC721 token to a user address.
    function transferFromParent(address _fromContract, uint256 _fromTokenId, address _to, uint256 _tokenId, bytes memory _data) external;
    // Transfers _tokenId from a parent ERC721 token to a parent ERC721 token.
    function transferAsChild(address _fromContract, uint256 _fromTokenId, address _toContract, uint256 _toTokenId, uint256 _tokenId, bytes memory _data) external;

}

/*
interface ERC998ERC721BottomUpNotifications {
    function onERC998Removed(address _operator, uint256 _parentTokenId, uint256 _childTokenId, bytes _data) external;
}
*/
interface IERC998ERC721BottomUpEnumerable {
    function totalChildTokens(address _parentContract, uint256 _parentTokenId) external view returns (uint256);

    function childTokenByIndex(address _parentContract, uint256 _parentTokenId, uint256 _index) external view returns (uint256);
}


contract NFTExperience is
    ERC721,
    ERC721Enumerable,
    ERC721URIStorage,
    ERC721Burnable,
    Ownable,
    IERC998ERC721BottomUp,
    IERC998ERC721BottomUpEnumerable
{
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

    constructor() ERC721("MyToken", "MTK") {}

    function safeMint(address to, string memory uri) public onlyOwner {
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);
    }

    // The following functions are overrides required by Solidity.

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function _burn(uint256 tokenId)
        internal
        override(ERC721, ERC721URIStorage)
    {
        super._burn(tokenId);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    // erc998 functions
    function _tokenOwnerOf(uint256 _tokenId)
        internal
        view
        returns (
            address tokenOwner,
            uint256 parentTokenId,
            bool isParent
        )
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

    function tokenOwnerOf(uint256 _tokenId)
        external
        view
        returns (
            bytes32 tokenOwner,
            uint256 parentTokenId,
            bool isParent
        )
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

    function rootOwnerOf(uint256 _tokenId)
        public
        view
        returns (bytes32 rootOwner)
    {
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
    function ownerOf(uint256 _tokenId)
        public
        view
        override(ERC721, IERC721)
        returns (address)
    {
        address tokenOwner = tokenIdToTokenOwner[_tokenId].tokenOwner;
        require(tokenOwner != address(0));
        return tokenOwner;
    }

    /** conversion functions */
    function uint256ToBytes32(uint256 x) public pure returns (bytes32 b) {
        b = bytes32(x);
    }

    function addressToBytes32(address _address)
        public
        pure
        returns (bytes32 _bytes)
    {
        _bytes = bytes32(uint256(uint160(_address)));
    }

    function transferToParent(
        address _from,
        address _toContract,
        uint256 _toTokenId,
        uint256 _tokenId,
        bytes memory _data
    ) external override {}

    function transferFromParent(
        address _fromContract,
        uint256 _fromTokenId,
        address _to,
        uint256 _tokenId,
        bytes memory _data
    ) external override {}

    function transferAsChild(
        address _fromContract,
        uint256 _fromTokenId,
        address _toContract,
        uint256 _toTokenId,
        uint256 _tokenId,
        bytes memory _data
    ) external override {}

    function totalChildTokens(address _parentContract, uint256 _parentTokenId)
        external
        view
        override
        returns (uint256)
    {}

    function childTokenByIndex(
        address _parentContract,
        uint256 _parentTokenId,
        uint256 _index
    ) external view override returns (uint256) {}
}

