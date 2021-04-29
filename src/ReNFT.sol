// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./interfaces/IResolver.sol";
import "./interfaces/IReNFT.sol";
import "hardhat/console.sol";

// - TODO: erc1155 amounts not supported in this version
// adding the amounts, would imply that lending struct would
// become two single storage slots, since it only has 4 bits
// of free space.
contract ReNFT is IReNft, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IResolver private resolver;
    address private admin;
    address payable private beneficiary;
    uint256 private lendingId = 1;

    uint256 public rentFee = 500;
    bytes4 private constant ERC20_DECIMALS_SELECTOR = bytes4(keccak256(bytes("decimals()")));

    // single storage slot: address - 160 bits, 176, 208, 240, 248, 256
    struct Lending {
        address payable lenderAddress;
        uint8 maxRentDuration;
        bytes4 dailyRentPrice;
        bytes4 nftPrice;
        uint8 lentAmount;
        uint8 availableAmount;
        IResolver.PaymentToken paymentToken;
    }

    // single storage slot: 160 bits, 176, 198, 206
    struct Renting {
        address payable renterAddress;
        uint8 rentDuration;
        uint32 rentedAt;
        uint8 amount;
    }

    struct LendingRenting {
        Lending lending;
        Renting renting;
    }

    struct TwoPointer {
        uint256 lastIx;
        uint256 currIx;
        uint256 endIx;
    }

    // 32 bytes key to 64 bytes struct
    mapping(bytes32 => LendingRenting) private lendingRenting;

    constructor(
        address _resolver,
        address payable _beneficiary,
        address _admin
    ) {
        resolver = IResolver(_resolver);
        beneficiary = _beneficiary;
        admin = _admin;
    }

    // Lightly brainy section ahead
    // ----
    // So here is a random joke from the Internet before you venture out
    // into split or double-split or gazillion-times-split screen to read
    // all the contracts and piece it all together (because I am bad
    // at remembering, or coming up with jokes)
    // Here comes the joke:
    // You don't need a parachute to go skydiving.
    // You need a parachute to go skydiving twice.
    // ----

    /**
     * amounts: if 0 then that is 721. For how and why we have implemented the below, see the pdf in the docs folder in
     * this repo. Titled optimal-1155-721-lend.pdf
     *
     * Batch transfers are performed even on single tokenId 1155 transactions because
     * marginal cost is 4k gas when compared to safeTransferFrom. And this cost is worth
     * the added complexity of the below function.
     * Please look into the docs folder again for some screenshots.
     */
    function lend(
        address[] memory _nft,
        uint256[] memory _tokenId,
        uint256[] memory _amounts,
        uint8[] memory _maxRentDuration,
        bytes4[] memory _dailyRentPrice,
        bytes4[] memory _nftPrice,
        IResolver.PaymentToken[] memory _paymentToken
    ) external override  {
        TwoPointer memory tp = TwoPointer({currIx: 0, lastIx: 0, endIx: _nft.length - 1});

        for (uint256 i = 0; i < _nft.length; i++) {
            address lastNftAddress = _nft[tp.lastIx];
            address currNftAddress = _nft[tp.currIx];
            bool endOfLoop = i == tp.endIx;

            if ((lastNftAddress == currNftAddress) && !endOfLoop) {
                // ! you can have two 721s in a row with the same address but different tokenIds
                // ! treat them as different by observing consecutive zero amounts
                // ! if two consecutive zeros, then this is the same 721 but with different tokenIds
                if ((tp.lastIx + 1 == tp.currIx) && (_amounts[tp.lastIx] == 0) && (_amounts[tp.currIx] == 0)) {
                    if (!_isERC721(lastNftAddress)) revert("incorrect usage");
                    _handleLend721(
                        lastNftAddress,
                        _tokenId[tp.lastIx],
                        _maxRentDuration[tp.lastIx],
                        _dailyRentPrice[tp.lastIx],
                        _nftPrice[tp.lastIx],
                        _paymentToken[tp.lastIx]
                    );
                    tp.lastIx = tp.currIx;
                    tp.currIx++;
                    continue;
                }
                // same addresses but not the final element, just continue
                continue;
            }

            // for the above to not be true, we need:
            // (a) the first condition to be false:  lastNftAddress != currNftAddress
            // (b) the second condition to be false: end of loop

            // (i)  lastNftAddress != currNftAddress. denote as event A
            // (ii) end of loop.                      denote as event B
            // which produces the set of the following scenarios
            // { (A and !B), (A and B), (!A and B) }
            // i.e. (different addresses and not end of loop),
            //      (different addresses and end of loop),
            //      (same      addresses and end of loop)
            // 1. usual spiel. if 721 send simply. if 1155 send batch etc. finally, set lastIx = currIx and currIx++.
            // 2. ditto above
            // 3. complex case. Can be broken down into a number of cases itself
            //    - the simplest:     different 721 addresses. Just handle both of them as per usual, but obviously 2 calls
            //    - more challenging: one is 721 and one is 1155
            //    - equally challening:  different 1155 addresses.

            _handleDRY(
                lastNftAddress,
                tp,
                _tokenId,
                _amounts,
                _maxRentDuration,
                _dailyRentPrice,
                _nftPrice,
                _paymentToken
            );

            if (endOfLoop && tp.endIx > 1) {
                _handleDRY(
                    currNftAddress,
                    tp,
                    _tokenId,
                    _amounts,
                    _maxRentDuration,
                    _dailyRentPrice,
                    _nftPrice,
                    _paymentToken
                );
                return;
            }
            tp.lastIx = tp.currIx;
            tp.currIx++;
        }
    }

    function _handleDRY(
        address _nft,
        TwoPointer memory _tp,
        uint256[] memory _tokenId,
        uint256[] memory _amounts,
        uint8[] memory _maxRentDuration,
        bytes4[] memory _dailyRentPrice,
        bytes4[] memory _nftPrice,
        IResolver.PaymentToken[] memory _paymentToken
    ) private {
        if (_isERC721(_nft)) {
            console.log("||||||| handling 721 |||||||");
            _handleLend721(
                _nft,
                _tokenId[_tp.lastIx],
                _maxRentDuration[_tp.lastIx],
                _dailyRentPrice[_tp.lastIx],
                _nftPrice[_tp.lastIx],
                _paymentToken[_tp.lastIx]
            );
        } else if (_isERC1155(_nft)) {
            console.log("||||||| handling 1155 |||||||");
            _handleLend1155(
                _nft,
                _tp,
                _tokenId,
                _amounts,
                _maxRentDuration,
                _dailyRentPrice,
                _nftPrice,
                _paymentToken
            );
        } else {
            revert("curr nft address is unsupported");
        }
    }

    function _handleLend(
        address _nft,
        uint256 _tokenId,
        uint8 _amount,
        uint8 _maxRentDuration,
        bytes4 _dailyRentPrice,
        bytes4 _nftPrice,
        IResolver.PaymentToken _paymentToken
    ) private {
        // will only occur if someone passed an amount greater than uint8. i.e. >= 256
        require(_amount > 0, "invalid lend amount");
        // to avoid stack too deep
        bool is721 = false;
        {
            console.log("||||||| I am a 721 |||||||");
            is721 = _isERC721(_nft);
        }
        bytes32 itemHash = keccak256(abi.encodePacked(_nft, _tokenId, _amount, lendingId));
        LendingRenting storage item = lendingRenting[itemHash];
        item.lending = Lending({
            lenderAddress: payable(msg.sender),
            lentAmount: _amount,
            availableAmount: _amount,
            maxRentDuration: _maxRentDuration,
            dailyRentPrice: _dailyRentPrice,
            nftPrice: _nftPrice,
            paymentToken: _paymentToken
        });
        emit Lent(
            _nft,
            _tokenId,
            lendingId,
            msg.sender,
            _maxRentDuration,
            _dailyRentPrice,
            _nftPrice,
            _amount,
            is721,
            _paymentToken
        );
        lendingId++;
    }

    function _handleLend721(
        address _nft,
        uint256 _tokenId,
        uint8 _maxRentDuration,
        bytes4 _dailyRentPrice,
        bytes4 _nftPrice,
        IResolver.PaymentToken _paymentToken
    ) private  {
        _handleLend(
            _nft,
            _tokenId,
            1,
            _maxRentDuration,
            _dailyRentPrice,
            _nftPrice,
            _paymentToken
        );
        IERC721(_nft).transferFrom(msg.sender, address(this), _tokenId);
    }

    function _handleLend1155(
        address _nft,
        TwoPointer memory _tp,
        uint256[] memory _tokenId,
        uint256[] memory _amounts,
        uint8[] memory _maxRentDuration,
        bytes4[] memory _dailyRentPrice,
        bytes4[] memory _nftPrice,
        IResolver.PaymentToken[] memory _paymentToken
    ) private {
        // emit individual Lend events
        for (uint256 i = _tp.currIx; i < _tp.endIx + 1; i++) {
            console.log("~~~~~~~~~~ handling a single 1155 lend ~~~~~~~~~~~");
            _handleLend(
                _nft,
                _tokenId[i],
                // if 256 and larger will convert to zero
                uint8(_amounts[i]),
                _maxRentDuration[i],
                _dailyRentPrice[i],
                _nftPrice[i],
                _paymentToken[i]
            );
        }
        IERC1155(_nft).safeBatchTransferFrom(msg.sender, address(this), _tokenId, _amounts, "");
    }

    function rent(
        address[] memory _nft,
        uint256[] memory _tokenId,
        uint256[] memory _id,
        uint8[] memory _rentDuration
    ) external payable override  {
        uint256 ethPmtRequired = 0;
        uint256 nftLen = _nft.length - 1;

        for (uint256 i = 0; i < _nft.length; i++) {
            address nft = _nft[i];
            uint256 tokenId = _tokenId[i];
            lendingId = _id[i];
            LendingRenting storage item = lendingRenting[keccak256(abi.encodePacked(nft, tokenId, lendingId))];

            _ensureIsNull(item.renting);
            require(msg.sender != item.lending.lenderAddress, "cant rent own nft");

            uint8 rentDuration = _rentDuration[i];
            require(rentDuration > 0, "should rent for at least a day");
            require(rentDuration <= item.lending.maxRentDuration, "max rent duration exceeded");

            uint8 paymentTokenIndex = uint8(item.lending.paymentToken);
            address paymentToken = resolver.getPaymentToken(paymentTokenIndex);
            bool isERC20 = paymentTokenIndex > 1;

            uint256 decimals = 18;
            if (isERC20) {
                decimals = _decimals(paymentToken);
            }

            {
                uint256 scale = 10**decimals;
                // max is 1825 * 65535. Nowhere near the overflow
                uint256 rentPrice = rentDuration * _unpackPrice(item.lending.dailyRentPrice, scale);
                uint256 nftPrice = _unpackPrice(item.lending.nftPrice, scale);
                require(rentPrice > 0, "rent price is zero");
                uint256 upfrontPayment = rentPrice + nftPrice;
                if (isERC20) {
                    IERC20(paymentToken).safeTransferFrom(msg.sender, address(this), upfrontPayment);
                } else {
                    ethPmtRequired += upfrontPayment;
                }
            }

            if (i == nftLen) {
                require(msg.value == ethPmtRequired, "insufficient amount");
            }

            item.renting.renterAddress = payable(msg.sender);
            item.renting.rentDuration = rentDuration;
            item.renting.rentedAt = uint32(block.timestamp);

            _safeTransfer(address(this), msg.sender, nft, tokenId);

            emit Rented(nft, tokenId, lendingId, msg.sender, rentDuration, _isERC721(nft), uint32(block.timestamp));
        }
    }

    function _takeFee(uint256 _rent, IResolver.PaymentToken _paymentToken) private returns (uint256 fee) {
        fee = _rent * rentFee;
        fee /= 10000; // percentages
        uint8 paymentTokenIx = uint8(_paymentToken);

        if (paymentTokenIx > 1) {
            IERC20 paymentToken = IERC20(resolver.getPaymentToken(paymentTokenIx));
            paymentToken.safeTransfer(beneficiary, fee);
        } else {
            beneficiary.transfer(fee);
        }
    }

    /**
     * @dev send rent amounts to lender, send unused
     * rent amonuts to renter. Send the collateral
     * back to renter. Fee is only ever charged on
     * used rent payments. Initially, it will be set at zero.
     * Gets called only when the NFT is returned.
     * _takeFee is here and in distributeClaimPayments.
     *
     * @param _lendingRenting when you return the NFT,
     * you will have provided the lendingId, with it,
     * as well as, nft address and token id, you can
     * uniquely identify an NFT on reNFT.
     * @param _secondsSinceRentStart seconds since rent
     * start
     */
    function _distributePayments(LendingRenting storage _lendingRenting, uint256 _secondsSinceRentStart) private {
        uint256 decimals = 18;
        uint8 paymentTokenIx = uint8(_lendingRenting.lending.paymentToken);
        address paymentToken = resolver.getPaymentToken(paymentTokenIx);
        bool isERC20 = paymentTokenIx > 1;

        if (isERC20) {
            decimals = _decimals(paymentToken);
        }

        uint256 scale = 10**decimals;
        uint256 nftPrice = _unpackPrice(_lendingRenting.lending.nftPrice, scale);
        uint256 rentPrice = _unpackPrice(_lendingRenting.lending.dailyRentPrice, scale);
        uint256 renterPayment = rentPrice * _lendingRenting.renting.rentDuration;
        uint256 sendLenderAmt = (_secondsSinceRentStart * rentPrice) / 86400;

        require(renterPayment >= sendLenderAmt, "lender receiving more than renter pmt");

        uint256 sendRenterAmt = renterPayment - sendLenderAmt;

        require(renterPayment > sendRenterAmt, "underflow issues prevention");

        uint256 takenFee = _takeFee(sendLenderAmt, _lendingRenting.lending.paymentToken);
        sendRenterAmt += nftPrice;

        if (isERC20) {
            IERC20(paymentToken).safeTransfer(_lendingRenting.lending.lenderAddress, sendLenderAmt - takenFee);
            IERC20(paymentToken).safeTransfer(_lendingRenting.renting.renterAddress, sendRenterAmt);
        } else {
            require(paymentTokenIx == 1, "sentinels dont pay");

            _lendingRenting.lending.lenderAddress.transfer(sendLenderAmt - takenFee);
            _lendingRenting.renting.renterAddress.transfer(sendRenterAmt);
        }
    }

    function _distributeClaimPayment(LendingRenting memory _lendingRenting) private {
        uint256 decimals = 18;
        uint8 paymentTokenIx = uint8(_lendingRenting.lending.paymentToken);
        IERC20 paymentToken = IERC20(resolver.getPaymentToken(paymentTokenIx));

        bool isERC20 = paymentTokenIx > 1;

        if (isERC20) {
            decimals = _decimals(address(paymentToken));
        }

        uint256 scale = 10**decimals;
        uint256 nftPrice = _unpackPrice(_lendingRenting.lending.nftPrice, scale);
        uint256 rentPrice = _unpackPrice(_lendingRenting.lending.dailyRentPrice, scale);
        uint256 maxRentPayment = rentPrice * _lendingRenting.renting.rentDuration;
        uint256 takenFee = _takeFee(maxRentPayment, IResolver.PaymentToken(paymentTokenIx));
        uint256 finalAmt = maxRentPayment + nftPrice;

        if (isERC20) {
            paymentToken.safeTransfer(_lendingRenting.lending.lenderAddress, finalAmt - takenFee);
        } else {
            _lendingRenting.lending.lenderAddress.transfer(finalAmt - takenFee);
        }
    }

    function returnIt(
        address[] memory _nft,
        uint256[] memory _tokenId,
        uint256[] memory _id
    ) public override  {
        for (uint256 i = 0; i < _nft.length; i++) {
            LendingRenting storage item = lendingRenting[keccak256(abi.encodePacked(_nft[i], _tokenId[i], _id[i]))];

            require(item.renting.renterAddress == msg.sender, "not renter");

            uint256 blockTimestamp = block.timestamp;
            bool isPastReturn = _isPastReturnDate(item.renting, blockTimestamp);
            require(!isPastReturn, "is past return date");

            uint256 secondsSinceRentStart = blockTimestamp - item.renting.rentedAt;

            _safeTransfer(msg.sender, address(this), _nft[i], _tokenId[i]);

            _distributePayments(item, secondsSinceRentStart);

            emit Returned(_nft[i], _tokenId[i], _id[i], msg.sender, uint32(block.timestamp));

            delete item.renting;
        }
    }

    function claimCollateral(
        address[] memory _nft,
        uint256[] memory _tokenId,
        uint256[] memory _id
    ) public override  {
        for (uint256 i = 0; i < _nft.length; i++) {
            LendingRenting storage item = lendingRenting[keccak256(abi.encodePacked(_nft[i], _tokenId[i], _id[i]))];

            require(_isPastReturnDate(item.renting, block.timestamp), "cant claim yet");
            _ensureIsNotNull(item.lending);
            _ensureIsNotNull(item.renting);
            _distributeClaimPayment(item);

            delete item.lending;
            delete item.renting;

            emit CollateralClaimed(_nft[i], _tokenId[i], _id[i], uint32(block.timestamp));
        }
    }

    function stopLending(
        address[] memory _nft,
        uint256[] memory _tokenId,
        uint256[] memory _id
    ) public override  {
        for (uint256 i = 0; i < _nft.length; i++) {
            LendingRenting storage item = lendingRenting[keccak256(abi.encodePacked(_nft[i], _tokenId[i], _id[i]))];

            _ensureIsNull(item.renting);

            require(item.lending.lenderAddress == msg.sender, "only lender allowed");

            _safeTransfer(address(this), msg.sender, _nft[i], _tokenId[i]);

            delete item.lending;

            emit LendingStopped(_nft[i], _tokenId[i], _id[i], uint32(block.timestamp));
        }
    }

    /**
     * @dev determines what nft standrad we are dealing with
     */
    function _safeTransfer(
        address _from,
        address _to,
        address _nft,
        uint256 _tokenId
    ) private {
        bool isERC721 = _isERC721(_nft);
        bool isERC1155 = _isERC1155(_nft);

        if (isERC721) {
            IERC721(_nft).transferFrom(_from, _to, _tokenId);
        } else if (isERC1155) {
            // TODO: change the amount
            IERC1155(_nft).safeTransferFrom(_from, _to, _tokenId, 1, "");
        } else {
            revert("unsupported _from");
        }
    }

    // We can handle erc1155s
    // ----
    // ┈╱╱▏┈┈╱╱╱╱▏╱╱▏┈┈┈
    // ┈▇╱▏┈┈▇▇▇╱▏▇╱▏┈┈┈
    // ┈▇╱▏▁┈▇╱▇╱▏▇╱▏▁┈┈
    // ┈▇╱╱╱▏▇╱▇╱▏▇╱╱╱▏┈
    // ┈▇▇▇╱┈▇▇▇╱┈▇▇▇╱┈┈
    // ----

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        // 0xf0b9e5ba === `bytes4(keccak256("onERC721Received(address,uint256,bytes)"))`
        // 0xf0b9e5ba === `ERC721Receiver(0).onERC721Received.selector`
        return 0xf0b9e5ba;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external pure override returns (bytes4) {
        // bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))`
        return 0xbc197c81;
    }

    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        // bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)")) = 0xf23a6e61
        // ! note that single 1155 receives are not supported. So if you send something
        // ! directly, it will be forever lost
        return 0xf23a6e61;
    }

    /**
     * @dev supports the following interfaces: IERC721Receiver, IERC1155Receiver
     */
    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return
            (interfaceId == type(IERC721Receiver).interfaceId) || (interfaceId == type(IERC1155Receiver).interfaceId);
    }

    // Utils
    // ----
    //
    // ___$$$___$$$____
    // __$$$$$_$$$$$___
    // __$$$$$$$$$$$___
    // ____$$$$$$$_____
    // ______$$$_______
    // _______$
    // _____¸.•´¸.•*¸.•*´¨`*•.♥
    // _____*.¸¸.•*¨`
    //
    // ----

    function _isERC721(address _nft) private view returns (bool) {
        return IERC165(_nft).supportsInterface(type(IERC721).interfaceId);
    }

    function _isERC1155(address _nft) private view returns (bool) {
        return IERC165(_nft).supportsInterface(type(IERC1155).interfaceId);
    }

    /**
     * @dev this was added to maintain single storage slot for lending
     *
     * @param _price packed price, 8 hex chars
     * @param _scale if 18 decimal places, then pass 1000000000000000000
     */
    function _unpackPrice(bytes4 _price, uint256 _scale) private pure returns (uint256) {
        uint16 whole = uint16(bytes2(_price));
        uint16 decimal = uint16(bytes2(_price << 16));
        uint256 decimalScale = _scale / 10000;
        if (whole > 9999) {
            whole = 9999;
        }
        uint256 w = whole * _scale;
        if (decimal > 9999) {
            decimal = 9999;
        }
        uint256 d = decimal * decimalScale;
        uint256 price = w + d;
        require(price >= w, "invalid price");
        if (price == 0) {
            price = decimalScale;
        }
        return price;
    }

    /**
     * @dev ERC20 does not specify a decimals function, and so expecting it to be there is incorrect
     * Our price packing implementation, however, requires us to know what this number is,
     * since it affects our arithmetic. This is imposed by the constrain of a single storage
     * slot lend.
     *
     * Notice that a DAO / delegated multi-sig will be controlling the Resolver, that implies that
     * unless maliciously overtaken, we will be in control of the payment tokens that we are adding.
     * As such, this function is an extra security measure, as well as a generalised way to get
     * decimals off ERC20.
     *
     *  @param _tokenAddress ERC20 token address for which to attempt to pull decimals
     */
    function _decimals(address _tokenAddress) private returns (uint256) {
        (bool success, bytes memory data) = _tokenAddress.call(abi.encodeWithSelector(ERC20_DECIMALS_SELECTOR));
        require(success, "invalid decimals call");
        uint256 decimals = abi.decode(data, (uint256));
        require(decimals > 0, "decimals cant be zero");
        return decimals;
    }

    // Sanity checks section
    // ----
    //   __
    //  /  |           /
    // (___| ___  ___ (___  ___  ___  ___
    // |    |   )|   )|    |___)|    |
    // |    |    |__/ |__  |__  |__  |__
    // ----

    function _ensureIsNotNull(Lending memory _lending) private pure {
        require(_lending.lenderAddress != address(0), "lender is zero address");
        require(_lending.maxRentDuration != 0, "max rent duration is zero");
        require(_lending.dailyRentPrice != 0, "daily rent price is zero");
        require(_lending.nftPrice != 0, "nft price is zero");
    }

    function _ensureIsNotNull(Renting memory _renting) private pure {
        require(_renting.renterAddress != address(0), "renter address is zero address");
        require(_renting.rentDuration != 0, "rent duration is zero");
        require(_renting.rentedAt != 0, "never rented");
    }

    function _ensureIsNull(Renting memory _renting) private pure {
        require(_renting.renterAddress == address(0), "renter address is not zero address");
        require(_renting.rentDuration == 0, "rent duration is not zero");
        require(_renting.rentedAt == 0, "is rented");
    }

    function _isPastReturnDate(Renting memory _renting, uint256 _now) private pure returns (bool) {
        return _now - _renting.rentedAt > _renting.rentDuration * 86400;
    }

    // Admin only section
    // ----
    //   __
    //  /  |    |      /                     /
    // (___| ___| _ _    ___       ___  ___ (
    // |   )|   )| | )| |   )     |   )|   )| \   )
    // |  / |__/ |  / | |  /      |__/ |  / |  \_/
    // ----                                    /

    function setRentFee(uint256 _rentFee) external {
        require(msg.sender == admin, "");
        require(_rentFee < 10000, "cannot be taking 100 pct fee madlad");
        rentFee = _rentFee;
    }

    function setBeneficiary(address payable _newBeneficiary) external {
        require(msg.sender == admin, "");
        beneficiary = _newBeneficiary;
    }
}
