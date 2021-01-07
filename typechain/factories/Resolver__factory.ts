/* Autogenerated file. Do not edit manually. */
/* tslint:disable */
/* eslint-disable */

import { Signer } from "ethers";
import { Provider, TransactionRequest } from "@ethersproject/providers";
import { Contract, ContractFactory, Overrides } from "@ethersproject/contracts";

import type { Resolver } from "../Resolver";

export class Resolver__factory extends ContractFactory {
  constructor(signer?: Signer) {
    super(_abi, _bytecode, signer);
  }

  deploy(overrides?: Overrides): Promise<Resolver> {
    return super.deploy(overrides || {}) as Promise<Resolver>;
  }
  getDeployTransaction(overrides?: Overrides): TransactionRequest {
    return super.getDeployTransaction(overrides || {});
  }
  attach(address: string): Resolver {
    return super.attach(address) as Resolver;
  }
  connect(signer: Signer): Resolver__factory {
    return super.connect(signer) as Resolver__factory;
  }
  static connect(
    address: string,
    signerOrProvider: Signer | Provider
  ): Resolver {
    return new Contract(address, _abi, signerOrProvider) as Resolver;
  }
}

const _abi = [
  {
    anonymous: false,
    inputs: [
      {
        indexed: true,
        internalType: "address",
        name: "previousOwner",
        type: "address",
      },
      {
        indexed: true,
        internalType: "address",
        name: "newOwner",
        type: "address",
      },
    ],
    name: "OwnershipTransferred",
    type: "event",
  },
  {
    inputs: [
      {
        internalType: "uint8",
        name: "_pt",
        type: "uint8",
      },
    ],
    name: "getPaymentToken",
    outputs: [
      {
        internalType: "contract IERC20",
        name: "",
        type: "address",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "owner",
    outputs: [
      {
        internalType: "address",
        name: "",
        type: "address",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "renounceOwnership",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "uint8",
        name: "_pt",
        type: "uint8",
      },
      {
        internalType: "contract IERC20",
        name: "_v",
        type: "address",
      },
    ],
    name: "setPaymentToken",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "newOwner",
        type: "address",
      },
    ],
    name: "transferOwnership",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
];

const _bytecode =
  "0x608060405234801561001057600080fd5b50600061001b61006a565b600080546001600160a01b0319166001600160a01b0383169081178255604051929350917f8be0079c531659141344cd1fd0a4f28419497f9722a3daafe3b4186f6b6457e0908290a35061006e565b3390565b6103f98061007d6000396000f3fe608060405234801561001057600080fd5b50600436106100575760003560e01c8063321c6aea1461005c578063715018a6146100715780638da5cb5b14610079578063c6ee427f14610097578063f2fde38b146100aa575b600080fd5b61006f61006a3660046102e6565b6100bd565b005b61006f61012e565b6100816101ad565b60405161008e919061031c565b60405180910390f35b6100816100a53660046102cc565b6101bc565b61006f6100b83660046102a9565b6101de565b6100c5610294565b6000546001600160a01b039081169116146100fb5760405162461bcd60e51b81526004016100f290610376565b60405180910390fd5b60ff91909116600090815260016020526040902080546001600160a01b0319166001600160a01b03909216919091179055565b610136610294565b6000546001600160a01b039081169116146101635760405162461bcd60e51b81526004016100f290610376565b600080546040516001600160a01b03909116907f8be0079c531659141344cd1fd0a4f28419497f9722a3daafe3b4186f6b6457e0908390a3600080546001600160a01b0319169055565b6000546001600160a01b031690565b60ff81166000908152600160205260409020546001600160a01b03165b919050565b6101e6610294565b6000546001600160a01b039081169116146102135760405162461bcd60e51b81526004016100f290610376565b6001600160a01b0381166102395760405162461bcd60e51b81526004016100f290610330565b600080546040516001600160a01b03808516939216917f8be0079c531659141344cd1fd0a4f28419497f9722a3daafe3b4186f6b6457e091a3600080546001600160a01b0319166001600160a01b0392909216919091179055565b3390565b803560ff811681146101d957600080fd5b6000602082840312156102ba578081fd5b81356102c5816103ab565b9392505050565b6000602082840312156102dd578081fd5b6102c582610298565b600080604083850312156102f8578081fd5b61030183610298565b91506020830135610311816103ab565b809150509250929050565b6001600160a01b0391909116815260200190565b60208082526026908201527f4f776e61626c653a206e6577206f776e657220697320746865207a65726f206160408201526564647265737360d01b606082015260800190565b6020808252818101527f4f776e61626c653a2063616c6c6572206973206e6f7420746865206f776e6572604082015260600190565b6001600160a01b03811681146103c057600080fd5b5056fea26469706673582212201b03da70ce3fedc4fdf699cc609927652acd197073175af55f4fdccea100888464736f6c63430008000033";
