//
//  BackForwardTableViewCell.swift
//  Client
//
//  Created by Tyler Lacroix on 5/17/16.
//  Copyright © 2016 Mozilla. All rights reserved.
//

import UIKit
import Storage

class BackForwardTableViewCell: UITableViewCell {
    
    let padding: CGFloat = 5
    var faviconView: UIImageView!
    var label: UILabel!
    var bg: UIView!
    
    private let bgColor = UIColor.init(colorLiteralRed: 0.7, green: 0.7, blue: 0.7, alpha: 1)
    
    var connectingForwards = true
    var connectingBackwards = true
    var currentTab = false  {
        didSet {
            if(currentTab) {
                label.font = UIFont(name:"HelveticaNeue-Bold", size: 12.0)
                bg.snp_updateConstraints { make in
                    make.height.equalTo(25)
                    make.width.equalTo(25)
                }
            }
        }
    }
    
    var site: Site? {
        didSet {
            if let s = site {
                faviconView.setIcon(s.icon, withPlaceholder: FaviconFetcher.defaultFavicon)
                label.text = s.title
                setNeedsLayout()
            }
        }
    }
    
    override init(style: UITableViewCellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = UIColor.clearColor()
        selectionStyle = .None
        
        let selectedView = UIView()
        selectedView.backgroundColor = UIColor.redColor()
        selectedBackgroundView =  selectedView;
        
        faviconView = UIImageView(image: FaviconFetcher.defaultFavicon)
        faviconView.backgroundColor = UIColor.whiteColor()
        contentView.addSubview(faviconView)
        
        label = UILabel(frame: CGRectZero)
        label.textColor = UIColor.blackColor()
        label.text = " "
        label.font = label.font.fontWithSize(12)
        contentView.addSubview(label)
        
        faviconView.snp_makeConstraints { make in
            make.height.equalTo(20)
            make.width.equalTo(20)
            make.centerY.equalTo(self)
            make.left.equalTo(self.snp_left).offset(20)
        }
        
        label.snp_makeConstraints { make in
            make.centerY.equalTo(self)
            make.left.equalTo(faviconView.snp_right).offset(20)
            make.right.equalTo(self.snp_right).offset(20)
        }
        
        bg = UIView(frame: CGRect.zero)
        bg.backgroundColor = bgColor
        
        self.addSubview(bg)
        self.sendSubviewToBack(bg)
        
        bg.snp_makeConstraints { make in
            make.height.equalTo(22)
            make.width.equalTo(22)
            make.centerX.equalTo(faviconView)
            make.centerY.equalTo(faviconView)
        }
        
    }
    
    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func drawRect(rect: CGRect) {
        let context = UIGraphicsGetCurrentContext();
        
        let startPoint = CGPointMake(rect.origin.x + 30, rect.origin.y + (connectingForwards ?  0 : rect.size.height/2))
        let endPoint   = CGPointMake(rect.origin.x + 30, rect.origin.y + rect.size.height - (connectingBackwards  ? 0 : rect.size.height/2) - 1)
        
        CGContextSaveGState(context)
        CGContextSetLineCap(context, CGLineCap.Square)
        CGContextSetStrokeColorWithColor(context, bgColor.CGColor);
        CGContextSetLineWidth(context, 1.0); // Set the line width here
        CGContextMoveToPoint(context, startPoint.x + 0.5, startPoint.y + 0.5);
        CGContextAddLineToPoint(context, endPoint.x + 0.5, endPoint.y + 0.5);
        CGContextStrokePath(context);
        CGContextRestoreGState(context);
    }
    
    override func setHighlighted(highlighted: Bool, animated: Bool) {
        if (highlighted) {
            self.backgroundColor = UIColor.init(colorLiteralRed: 0, green: 0, blue: 0, alpha: 0.1)
        }
        else {
            self.backgroundColor = UIColor.clearColor()
        }
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        connectingForwards = true
        connectingBackwards = true
        currentTab = false
        label.font = UIFont(name:"HelveticaNeue", size: 12.0)
        
        bg.snp_updateConstraints { make in
            make.height.equalTo(22)
            make.width.equalTo(22)
        }
    }
}