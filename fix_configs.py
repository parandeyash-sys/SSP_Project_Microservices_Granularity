import os
import glob

replacements = {
    '"github.com/ServiceWeaver/onlineboutique/frontend/T"': '"github.com/ServiceWeaver/weaver/Main"',
    '"github.com/ServiceWeaver/onlineboutique/adservice/T"': '"github.com/ServiceWeaver/onlineboutique/adservice/AdService"',
    '"github.com/ServiceWeaver/onlineboutique/cartservice/T"': '"github.com/ServiceWeaver/onlineboutique/cartservice/CartService"',
    '"github.com/ServiceWeaver/onlineboutique/checkoutservice/T"': '"github.com/ServiceWeaver/onlineboutique/checkoutservice/CheckoutService"',
    '"github.com/ServiceWeaver/onlineboutique/currencyservice/T"': '"github.com/ServiceWeaver/onlineboutique/currencyservice/CurrencyService"',
    '"github.com/ServiceWeaver/onlineboutique/emailservice/T"': '"github.com/ServiceWeaver/onlineboutique/emailservice/EmailService"',
    '"github.com/ServiceWeaver/onlineboutique/paymentservice/T"': '"github.com/ServiceWeaver/onlineboutique/paymentservice/PaymentService"',
    '"github.com/ServiceWeaver/onlineboutique/productcatalogservice/T"': '"github.com/ServiceWeaver/onlineboutique/productcatalogservice/ProductCatalogService"',
    '"github.com/ServiceWeaver/onlineboutique/recommendationservice/T"': '"github.com/ServiceWeaver/onlineboutique/recommendationservice/RecommendationService"',
    '"github.com/ServiceWeaver/onlineboutique/shippingservice/T"': '"github.com/ServiceWeaver/onlineboutique/shippingservice/ShippingService"',
}

files = glob.glob('configs/*.toml') + glob.glob('configs/*.yaml')
for file_path in files:
    with open(file_path, 'r') as f:
        content = f.read()
    
    for old_str, new_str in replacements.items():
        content = content.replace(old_str, new_str)
        
    with open(file_path, 'w') as f:
        f.write(content)

print(f"Fixed {len(files)} config files.")
