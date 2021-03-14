//
//  MxAttributesStatus.swift
//  MICO
//
//  Created by William Xu on 2020/7/22.
//  Copyright © 2020 MXCHIP Co;Ltd. All rights reserved.
//

import Foundation
import nRFMeshProvision

protocol MxAttributeStatusMessage: MxMessage {
    var attributes: [MxGenericAttribute] { get }
    var tid: UInt8 { get }
    init(tid: UInt8, attributes: [MxGenericAttribute])
}

extension MxAttributeStatusMessage {
    var parameters: Data? {
        var data = Data()
        
        attributes.forEach{
            if let pdu = $0.pdu {
                 data += pdu
            }
        }
        
        guard !data.isEmpty else {
            return nil
        }
        
        return Data([tid]) + data
    }

    init?(parameters: Data) {
        /// Should have tid and at least one attribute type and value pair
        guard parameters.count >= 3 else {
            return nil
        }
        var attributes: [MxGenericAttribute] = []
        var index = 1

        while index < parameters.count {
            guard let attribute = MxAttribute.decode(pdu: parameters.subdata(in: index..<parameters.count))  else {
                return nil
            }
            attributes.append(attribute)
            
            guard case let fixedLengthAttribute as MxFixedLengthAttribute = attribute else { break }
            index += fixedLengthAttribute.length
            
        }
        
        self.init(tid: parameters[0], attributes: attributes)
    }
}


struct MxAttributesStatus: MxAttributeStatusMessage {
    
    static let opCode: UInt32 = 0xD32209
    
    var attributes: [MxGenericAttribute]
    var tid: UInt8
    
    init(tid: UInt8, attributes: [MxGenericAttribute]) {
        self.attributes = attributes
        self.tid = tid
    }
    
}

struct MxHeartbeat: MxAttributeStatusMessage {

    static let opCode: UInt32 = 0xD42209
    
    var attributes: [MxGenericAttribute]
    var tid: UInt8
    
    init(tid: UInt8, attributes: [MxGenericAttribute]) {
        self.attributes = attributes
        self.tid = tid
    }
    
}
    